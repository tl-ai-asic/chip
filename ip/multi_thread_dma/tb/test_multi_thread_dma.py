from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

from dv_lib import CsrInitiator
from dv_lib.memory import MemoryModel
from dv_lib.req_rsp_bus import MemoryReadTarget, MemoryWriteTarget


THREAD_COUNT = 4
THREAD_STRIDE = 0x20
MAX_OUTSTANDING_READS = 4
MAX_OUTSTANDING_WRITES = 3
SLOT_COUNT = MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES
MAX_TRANSFER_WORDS = 256

REG_SRC_ADDR = 0x00
REG_DST_ADDR = 0x04
REG_LEN_WORDS = 0x08
REG_CTRL = 0x0C
REG_STATUS = 0x10
REG_WORDS_DONE = 0x14
REG_INVALID = 0x18
INVALID_THREAD_ADDR = 0xE0


@dataclass(frozen=True)
class ThreadDescriptor:
    name: str
    thread_id: int
    src_addr: int
    dst_addr: int
    length_words: int
    seed: int
    irq_en: bool = True


class MultiThreadDmaCsrAgent:
    def __init__(self, dut):
        self.dut = dut
        self.bus = CsrInitiator(
            dut.clk,
            dut.cfg_valid,
            dut.cfg_write,
            dut.cfg_addr,
            dut.cfg_wdata,
            dut.cfg_ready,
            dut.cfg_rvalid,
            dut.cfg_rdata,
        )

    def idle(self):
        self.bus.idle()

    def addr(self, thread_id, offset):
        return thread_id * THREAD_STRIDE + offset

    async def write(self, thread_id, offset, data):
        await self.bus.write_addr(self.addr(thread_id, offset), data)

    async def read(self, thread_id, offset):
        return await self.bus.read_addr(self.addr(thread_id, offset))

    async def program_descriptor(self, descriptor, start=True):
        await self.write(descriptor.thread_id, REG_SRC_ADDR, descriptor.src_addr)
        await self.write(descriptor.thread_id, REG_DST_ADDR, descriptor.dst_addr)
        await self.write(descriptor.thread_id, REG_LEN_WORDS, descriptor.length_words)
        if start:
            await self.start_thread(descriptor.thread_id, descriptor.irq_en)

    async def start_thread(self, thread_id, irq_en=True):
        ctrl = 0x1 | (0x2 if irq_en else 0)
        await self.write(thread_id, REG_CTRL, ctrl)

    async def status(self, thread_id):
        value = await self.read(thread_id, REG_STATUS)
        return {
            "raw": value,
            "busy": bool(value & 0x1),
            "done": bool(value & 0x2),
            "error": bool(value & 0x4),
        }

    async def words_done(self, thread_id):
        return await self.read(thread_id, REG_WORDS_DONE)

    async def clear_done(self, thread_id):
        await self.write(thread_id, REG_STATUS, 0x2)

    async def clear_error(self, thread_id):
        await self.write(thread_id, REG_STATUS, 0x4)

    async def read_addr(self, addr):
        return await self.bus.read_addr(addr)

    async def write_addr(self, addr, data):
        await self.bus.write_addr(addr, data)

    async def wait_done(self, thread_id, use_interrupt=True, timeout_cycles=1000):
        irq_mask = 1 << thread_id
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if use_interrupt and (int(self.dut.irq_done.value) & irq_mask):
                return await self.status(thread_id)

            if not use_interrupt:
                status = await self.status(thread_id)
                if status["done"]:
                    return status

        raise TimeoutError(f"thread {thread_id} did not complete before timeout")

    async def wait_all_done(self, descriptors, timeout_cycles=3000):
        remaining = {descriptor.thread_id: descriptor for descriptor in descriptors}
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            irq_done = int(self.dut.irq_done.value)
            for thread_id in list(remaining):
                descriptor = remaining[thread_id]
                if descriptor.irq_en and (irq_done & (1 << thread_id)):
                    remaining.pop(thread_id)
                    continue
                if not descriptor.irq_en:
                    status = await self.status(thread_id)
                    if status["done"]:
                        remaining.pop(thread_id)

            if not remaining:
                return

        names = ", ".join(descriptor.name for descriptor in remaining.values())
        raise TimeoutError(f"threads did not complete before timeout: {names}")


class MultiThreadDmaEnv:
    def __init__(self, dut):
        self.dut = dut
        self.memory = MemoryModel(data_width=32)
        self.csr = MultiThreadDmaCsrAgent(dut)
        self.read_target = MemoryReadTarget(
            dut.clk,
            dut.rst_n,
            self.memory,
            dut.rd_req_valid,
            dut.rd_req_ready,
            dut.rd_req_id,
            dut.rd_req_addr,
            dut.rd_rsp_valid,
            dut.rd_rsp_ready,
            dut.rd_rsp_id,
            dut.rd_rsp_data,
            out_of_order_response=True,
            out_of_order_fast_delay=1,
            out_of_order_slow_delay=5,
        )
        self.write_target = MemoryWriteTarget(
            dut.clk,
            dut.rst_n,
            self.memory,
            dut.wr_req_valid,
            dut.wr_req_ready,
            dut.wr_req_id,
            dut.wr_req_addr,
            dut.wr_req_data,
            dut.wr_rsp_valid,
            dut.wr_rsp_ready,
            dut.wr_rsp_id,
            out_of_order_response=True,
            out_of_order_fast_delay=4,
            out_of_order_slow_delay=12,
        )

    def idle(self):
        self.csr.idle()
        self.read_target.idle()
        self.write_target.idle()

    async def start(self):
        cocotb.start_soon(self.read_target.run())
        cocotb.start_soon(self.write_target.run())

    async def reset(self):
        self.idle()
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)

    def reset_bus_activity(self):
        self.read_target.reset_activity()
        self.write_target.reset_activity()

    def snapshot_bus_activity(self):
        return {
            "read_accepted": len(self.read_target.accepted),
            "read_responses": len(self.read_target.responses),
            "write_accepted": len(self.write_target.accepted),
            "write_responses": len(self.write_target.responses),
        }

    def check_bus_activity_unchanged(self, before, context):
        after = self.snapshot_bus_activity()
        assert after == before, (
            f"{context}: unexpected memory traffic: before={before} after={after}"
        )

    def load_descriptor(self, descriptor):
        self.memory.load_random(
            descriptor.src_addr,
            descriptor.length_words,
            descriptor.seed,
        )

    def check_copy(self, descriptor):
        mismatches = self.memory.compare_words(
            descriptor.src_addr,
            descriptor.dst_addr,
            descriptor.length_words,
        )
        assert not mismatches, "\n".join(
            f"{descriptor.name} word {index}: src=0x{src:08x} dst=0x{dst:08x}"
            for index, src, dst in mismatches
        )

    async def check_completed_descriptor(self, descriptor):
        status = await self.csr.status(descriptor.thread_id)
        assert status["done"], f"{descriptor.name}: done bit not set"
        assert not status["busy"], f"{descriptor.name}: busy bit still set"
        assert not status["error"], (
            f"{descriptor.name}: unexpected error status 0x{status['raw']:08x}"
        )
        words_done = await self.csr.words_done(descriptor.thread_id)
        assert words_done == descriptor.length_words, (
            f"{descriptor.name}: WORDS_DONE={words_done}, "
            f"expected {descriptor.length_words}"
        )
        if descriptor.length_words:
            self.check_copy(descriptor)

    async def wait_multiple_threads_busy(self, timeout_cycles=500):
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if int(self.dut.busy_q.value).bit_count() > 1:
                return
        raise AssertionError("multiple DMA threads were not busy at the same time")

    async def wait_shared_id_pool_full(self, timeout_cycles=1000):
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if int(self.dut.id_pool.in_use_q.value).bit_count() == SLOT_COUNT:
                return
        raise AssertionError("shared ID pool never reached full occupancy")

    async def run_single_descriptor(self, descriptor):
        self.reset_bus_activity()
        before_reads = len(self.read_target.accepted)
        before_writes = len(self.write_target.accepted)
        self.load_descriptor(descriptor)

        await self.csr.program_descriptor(descriptor)
        status = await self.csr.wait_done(
            descriptor.thread_id,
            use_interrupt=descriptor.irq_en,
            timeout_cycles=max(1000, descriptor.length_words * 50 + 200),
        )
        assert status["done"], f"{descriptor.name}: done bit not set"
        await self.check_completed_descriptor(descriptor)

        if descriptor.length_words == 0:
            assert len(self.read_target.accepted) == before_reads
            assert len(self.write_target.accepted) == before_writes

        await self.csr.clear_done(descriptor.thread_id)
        status = await self.csr.status(descriptor.thread_id)
        assert not status["done"], f"{descriptor.name}: done bit did not clear"

    async def run_parallel_descriptors(self, descriptors, expect_id_pool_full=False):
        self.reset_bus_activity()
        for descriptor in descriptors:
            self.load_descriptor(descriptor)
            await self.csr.program_descriptor(descriptor, start=False)

        for descriptor in descriptors:
            await self.csr.start_thread(descriptor.thread_id, descriptor.irq_en)

        await self.wait_multiple_threads_busy()
        if expect_id_pool_full:
            await self.wait_shared_id_pool_full()

        timeout_cycles = max(3000, max(d.length_words for d in descriptors) * 120 + 1000)
        await self.csr.wait_all_done(descriptors, timeout_cycles=timeout_cycles)

        for descriptor in descriptors:
            await self.check_completed_descriptor(descriptor)
            await self.csr.clear_done(descriptor.thread_id)

    async def run_invalid_access_tests(self):
        self.reset_bus_activity()
        before = self.snapshot_bus_activity()

        read_data = await self.csr.read(0, REG_INVALID)
        assert read_data == 0, (
            f"invalid CSR offset read returned non-zero data: data=0x{read_data:08x}"
        )
        status = await self.csr.status(0)
        assert status["error"], "invalid CSR offset read did not set thread 0 error"
        assert not status["busy"], "invalid CSR offset read unexpectedly set busy"
        assert not status["done"], "invalid CSR offset read unexpectedly set done"
        self.check_bus_activity_unchanged(before, "invalid CSR offset read")
        await self.csr.clear_error(0)
        status = await self.csr.status(0)
        assert not status["error"], "invalid CSR offset read error did not clear"

        await self.csr.write(1, REG_INVALID, 0xA5A5_5A5A)
        status = await self.csr.status(1)
        assert status["error"], "invalid CSR offset write did not set thread 1 error"
        assert not status["busy"], "invalid CSR offset write unexpectedly set busy"
        assert not status["done"], "invalid CSR offset write unexpectedly set done"
        self.check_bus_activity_unchanged(before, "invalid CSR offset write")
        await self.csr.clear_error(1)
        status = await self.csr.status(1)
        assert not status["error"], "invalid CSR offset write error did not clear"

        words_done_before = await self.csr.words_done(2)
        await self.csr.write(2, REG_WORDS_DONE, 0x1)
        status = await self.csr.status(2)
        assert status["error"], "WORDS_DONE write did not set thread 2 error"
        assert not status["busy"], "WORDS_DONE write unexpectedly set busy"
        assert not status["done"], "WORDS_DONE write unexpectedly set done"
        words_done_after = await self.csr.words_done(2)
        assert words_done_after == words_done_before, (
            "WORDS_DONE write changed the read-only progress register"
        )
        self.check_bus_activity_unchanged(before, "WORDS_DONE write")
        await self.csr.clear_error(2)
        status = await self.csr.status(2)
        assert not status["error"], "WORDS_DONE write error did not clear"

        read_data = await self.csr.read_addr(INVALID_THREAD_ADDR)
        assert read_data == 0, (
            f"invalid thread CSR read returned non-zero data: data=0x{read_data:08x}"
        )
        status = await self.csr.status(0)
        assert status["error"], "invalid thread read did not set thread 0 error"
        assert not status["busy"], "invalid thread read unexpectedly set busy"
        assert not status["done"], "invalid thread read unexpectedly set done"
        self.check_bus_activity_unchanged(before, "invalid thread read")
        await self.csr.clear_error(0)
        status = await self.csr.status(0)
        assert not status["error"], "invalid thread read error did not clear"

        await self.csr.write_addr(INVALID_THREAD_ADDR, 0x5A5A_A5A5)
        status = await self.csr.status(0)
        assert status["error"], "invalid thread write did not set thread 0 error"
        assert not status["busy"], "invalid thread write unexpectedly set busy"
        assert not status["done"], "invalid thread write unexpectedly set done"
        self.check_bus_activity_unchanged(before, "invalid thread write")
        await self.csr.clear_error(0)
        status = await self.csr.status(0)
        assert not status["error"], "invalid thread write error did not clear"

    async def run_illegal_descriptor(self, descriptor):
        self.reset_bus_activity()
        before_reads = len(self.read_target.accepted)
        before_writes = len(self.write_target.accepted)

        await self.csr.program_descriptor(descriptor)
        await ClockCycles(self.dut.clk, 4)
        status = await self.csr.status(descriptor.thread_id)
        assert status["error"], (
            f"{descriptor.name}: illegal descriptor did not set error"
        )
        assert not status["busy"], (
            f"{descriptor.name}: illegal descriptor unexpectedly started"
        )
        assert not status["done"], (
            f"{descriptor.name}: illegal descriptor unexpectedly completed"
        )
        assert int(self.dut.irq_error.value) & (1 << descriptor.thread_id), (
            f"{descriptor.name}: irq_error did not assert for rejected thread"
        )
        assert len(self.read_target.accepted) == before_reads, (
            f"{descriptor.name}: rejected descriptor issued read traffic"
        )
        assert len(self.write_target.accepted) == before_writes, (
            f"{descriptor.name}: rejected descriptor issued write traffic"
        )
        words_done = await self.csr.words_done(descriptor.thread_id)
        assert words_done == 0, (
            f"{descriptor.name}: rejected descriptor changed WORDS_DONE to {words_done}"
        )
        await self.csr.clear_error(descriptor.thread_id)
        status = await self.csr.status(descriptor.thread_id)
        assert not status["error"], f"{descriptor.name}: error bit did not clear"
        assert not int(self.dut.irq_error.value) & (1 << descriptor.thread_id), (
            f"{descriptor.name}: irq_error did not clear"
        )

    async def run_busy_csr_write_error_test(self, descriptors):
        read_policy = self.read_target.delay_policy
        write_policy = self.write_target.delay_policy
        saved_read = (
            read_policy.response_delay,
            read_policy.response_latency,
            read_policy.out_of_order_response,
        )
        saved_write = (
            write_policy.response_delay,
            write_policy.response_latency,
            write_policy.out_of_order_response,
        )

        try:
            read_policy.response_delay = lambda _req, _sequence: 40
            read_policy.response_latency = 0
            read_policy.out_of_order_response = False
            write_policy.response_delay = lambda _req, _sequence: 40
            write_policy.response_latency = 0
            write_policy.out_of_order_response = False

            for descriptor in descriptors:
                self.load_descriptor(descriptor)
                await self.csr.program_descriptor(descriptor, start=False)
            for descriptor in descriptors:
                await self.csr.start_thread(descriptor.thread_id)
            await self.wait_multiple_threads_busy()

            protected_writes = [
                (
                    REG_SRC_ADDR,
                    descriptors[0].src_addr ^ 0x40,
                    descriptors[0].src_addr,
                    "SRC_ADDR",
                ),
                (
                    REG_DST_ADDR,
                    descriptors[0].dst_addr ^ 0x40,
                    descriptors[0].dst_addr,
                    "DST_ADDR",
                ),
                (
                    REG_LEN_WORDS,
                    descriptors[0].length_words + 1,
                    descriptors[0].length_words,
                    "LEN_WORDS",
                ),
            ]

            for offset, data, expected, name in protected_writes:
                await self.csr.write(descriptors[0].thread_id, offset, data)
                status0 = await self.csr.status(descriptors[0].thread_id)
                status1 = await self.csr.status(descriptors[1].thread_id)
                actual = await self.csr.read(descriptors[0].thread_id, offset)
                assert status0["error"], (
                    f"busy write to {name} did not set thread 0 error"
                )
                assert not status1["error"], (
                    f"busy write to {name} leaked error into thread 1"
                )
                assert status0["busy"], f"thread 0 stopped after busy write to {name}"
                assert status1["busy"], f"thread 1 stopped after busy write to {name}"
                assert actual == expected, (
                    f"busy write to {name} changed descriptor value: "
                    f"expected=0x{expected:08x} actual=0x{actual:08x}"
                )
                await self.csr.clear_error(descriptors[0].thread_id)
                status0 = await self.csr.status(descriptors[0].thread_id)
                assert not status0["error"], (
                    f"busy write to {name} error did not clear"
                )

            await self.csr.wait_all_done(descriptors, timeout_cycles=6000)
            for descriptor in descriptors:
                await self.check_completed_descriptor(descriptor)
                await self.csr.clear_done(descriptor.thread_id)
        finally:
            (
                read_policy.response_delay,
                read_policy.response_latency,
                read_policy.out_of_order_response,
            ) = saved_read
            (
                write_policy.response_delay,
                write_policy.response_latency,
                write_policy.out_of_order_response,
            ) = saved_write


@cocotb.test()
async def multi_thread_dma_suite(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    env = MultiThreadDmaEnv(dut)
    await env.start()
    await env.reset()
    await env.run_invalid_access_tests()

    await env.run_single_descriptor(
        ThreadDescriptor("thread0_zero_words", 0, 0x0000, 0x4000, 0, 0xA000_0000)
    )
    await env.run_single_descriptor(
        ThreadDescriptor("thread2_single_word", 2, 0x0100, 0x5000, 1, 0xA100_0000)
    )

    parallel = [
        ThreadDescriptor("thread0_parallel", 0, 0x1000, 0x8000, 32, 0xB000_0000),
        ThreadDescriptor("thread1_parallel", 1, 0x2000, 0x9000, 24, 0xB100_0000),
        ThreadDescriptor("thread2_parallel", 2, 0x3000, 0xA000, 28, 0xB200_0000),
        ThreadDescriptor("thread3_parallel", 3, 0x4000, 0xB000, 20, 0xB300_0000),
    ]
    await env.run_parallel_descriptors(parallel, expect_id_pool_full=True)
    assert env.read_target.max_outstanding >= MAX_OUTSTANDING_READS, (
        f"expected {MAX_OUTSTANDING_READS} outstanding reads, "
        f"saw {env.read_target.max_outstanding}"
    )
    assert env.write_target.max_outstanding >= MAX_OUTSTANDING_WRITES, (
        f"expected {MAX_OUTSTANDING_WRITES} outstanding writes, "
        f"saw {env.write_target.max_outstanding}"
    )

    await env.run_busy_csr_write_error_test(
        [
            ThreadDescriptor("thread0_busy_error", 0, 0x5000, 0xC000, 64, 0xC000_0000),
            ThreadDescriptor("thread1_keeps_running", 1, 0x6000, 0xD000, 64, 0xC100_0000),
        ]
    )

    await env.run_illegal_descriptor(
        ThreadDescriptor(
            "thread2_over_max_transfer_words",
            2,
            0x7000,
            0xD800,
            MAX_TRANSFER_WORDS + 1,
            0xD000_0000,
        )
    )

    await env.run_illegal_descriptor(
        ThreadDescriptor(
            "thread3_overlap_rejected",
            3,
            0x7800,
            0x7808,
            8,
            0xD100_0000,
        )
    )
