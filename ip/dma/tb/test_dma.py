from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

from dv_lib import (
    CsrBlock,
    CsrCommonTester,
    CsrInitiator,
    CsrReg,
    CsrRegField,
    CsrRegFrontdoor,
)
from dv_lib.memory import MemoryModel
from dv_lib.req_rsp_bus import MemoryReadTarget, MemoryWriteTarget


MAX_OUTSTANDING_READS = 4
MAX_OUTSTANDING_WRITES = 3
SLOT_COUNT = MAX_OUTSTANDING_READS + MAX_OUTSTANDING_WRITES
MAX_TRANSFER_WORDS = 4096
ADDR_WIDTH = 16
INVALID_CSR_ADDR = 0xE0


@dataclass(frozen=True)
class DmaDescriptor:
    name: str
    src_addr: int
    dst_addr: int
    length_words: int
    seed: int
    irq_en: bool = True


def build_dma_csr_model():
    block = CsrBlock("dma")
    block.add_reg(CsrReg("SRC_ADDR", 0x00, width=ADDR_WIDTH))
    block.add_reg(CsrReg("DST_ADDR", 0x04, width=ADDR_WIDTH))
    block.add_reg(CsrReg("LEN_WORDS", 0x08))

    ctrl = block.add_reg(CsrReg("CTRL", 0x0C))
    ctrl.add_field(CsrRegField("start", 0, access="wo", compare=False, test=False))
    ctrl.add_field(CsrRegField("irq_en", 1))

    status = block.add_reg(CsrReg("STATUS", 0x10, access="ro"))
    status.add_field(CsrRegField("busy", 0, access="ro"))
    status.add_field(CsrRegField("done", 1, access="w1c"))
    status.add_field(CsrRegField("error", 2, access="w1c"))

    return block


class DmaCsrAgent:
    def __init__(self, dut):
        self.dut = dut
        self.model = build_dma_csr_model()
        self.src_addr = self.model.reg("SRC_ADDR")
        self.dst_addr = self.model.reg("DST_ADDR")
        self.len_words = self.model.reg("LEN_WORDS")
        self.ctrl = self.model.reg("CTRL")
        self.status = self.model.reg("STATUS")
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
        self.frontdoor = CsrRegFrontdoor(self.bus)
        self.common = CsrCommonTester(self.model, self.frontdoor)

    def idle(self):
        self.bus.idle()

    async def program_descriptor(self, descriptor):
        await self.frontdoor.write(self.src_addr, descriptor.src_addr)
        await self.frontdoor.write(self.dst_addr, descriptor.dst_addr)
        await self.frontdoor.write(self.len_words, descriptor.length_words)
        ctrl = self.ctrl.encode(start=1, irq_en=int(descriptor.irq_en))
        await self.frontdoor.write(self.ctrl, ctrl)

    async def read_status(self):
        return await self.frontdoor.read(self.status)

    async def read_status_fields(self):
        return self.status.decode(await self.read_status())

    async def wait_done(self, use_interrupt=True, timeout_cycles=1000):
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if use_interrupt and int(self.dut.irq_done.value):
                return await self.read_status()

            if not use_interrupt:
                fields = await self.read_status_fields()
                if fields["done"]:
                    return await self.read_status()

        raise TimeoutError("DMA did not complete before timeout")

    async def clear_done(self):
        await self.frontdoor.write(self.status, self.status.encode(done=1))

    async def clear_error(self):
        await self.frontdoor.write(self.status, self.status.encode(error=1))

    async def run_invalid_access_tests(self):
        read_data = await self.bus.read_addr(INVALID_CSR_ADDR)
        assert read_data == 0, (
            f"invalid CSR read returned non-zero data: data=0x{read_data:08x}"
        )
        status = await self.read_status()
        status_fields = self.status.decode(status)
        assert status_fields["error"], (
            f"invalid CSR read did not set error status: status=0x{status:08x}"
        )
        assert not status_fields["busy"], (
            f"invalid CSR read unexpectedly set busy: status=0x{status:08x}"
        )
        await self.clear_error()

        await self.bus.write_addr(INVALID_CSR_ADDR, 0xA5A5_5A5A)
        status = await self.read_status()
        status_fields = self.status.decode(status)
        assert status_fields["error"], (
            f"invalid CSR write did not set error status: status=0x{status:08x}"
        )
        assert not status_fields["busy"], (
            f"invalid CSR write unexpectedly set busy: status=0x{status:08x}"
        )
        await self.clear_error()

    async def run_common_access_tests(self):
        await self.common.check_reset()
        await self.common.check_read_write_access()


class DmaEnv:
    def __init__(self, dut):
        self.dut = dut
        self.memory = MemoryModel(data_width=32)
        self.csr = DmaCsrAgent(dut)
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

    def check_copy(self, descriptor):
        mismatches = self.memory.compare_words(
            descriptor.src_addr,
            descriptor.dst_addr,
            descriptor.length_words,
        )
        assert not mismatches, "\n".join(
            f"word {index}: src=0x{src:08x} dst=0x{dst:08x}"
            for index, src, dst in mismatches
        )

    def snapshot_bus_activity(self):
        return {
            "read_accepted": len(self.read_target.accepted),
            "read_responses": len(self.read_target.responses),
            "write_accepted": len(self.write_target.accepted),
            "write_responses": len(self.write_target.responses),
        }

    def reset_bus_activity(self):
        self.read_target.reset_activity()
        self.write_target.reset_activity()

    def check_zero_length_activity(self, before, after):
        assert after == before, (
            "zero-length DMA should not initiate memory traffic: "
            f"before={before} after={after}"
        )

    def check_out_of_order_activity(self, descriptor, before):
        read_accepted = self.read_target.accepted[before["read_accepted"]:]
        read_responses = self.read_target.responses[before["read_responses"]:]
        write_accepted = self.write_target.accepted[before["write_accepted"]:]
        write_responses = self.write_target.responses[before["write_responses"]:]

        assert read_responses, f"{descriptor.name}: no read responses observed"
        assert write_accepted, f"{descriptor.name}: no write requests observed"
        assert write_responses, f"{descriptor.name}: no write responses observed"

        first_read_id = read_accepted[0]["id"]
        assert read_responses[0] != first_read_id, (
            f"{descriptor.name}: expected first read response to be returned out of order"
        )
        assert write_accepted[0]["addr"] != descriptor.dst_addr, (
            f"{descriptor.name}: expected first write request to be issued out of "
            "destination order"
        )
        accepted_write_ids = [req["id"] for req in write_accepted]
        assert write_responses != accepted_write_ids, (
            f"{descriptor.name}: expected write responses to be returned out of "
            "accepted request order"
        )
        assert self.read_target.max_outstanding >= MAX_OUTSTANDING_READS, (
            f"expected read target to observe {MAX_OUTSTANDING_READS} outstanding reads, "
            f"saw {self.read_target.max_outstanding}"
        )
        assert self.write_target.max_outstanding >= MAX_OUTSTANDING_WRITES, (
            f"expected write target to observe {MAX_OUTSTANDING_WRITES} outstanding writes, "
            f"saw {self.write_target.max_outstanding}"
        )

    async def wait_all_ids_in_use(self, descriptor, timeout_cycles=500):
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if (
                self.read_target.outstanding >= MAX_OUTSTANDING_READS
                and self.write_target.outstanding >= MAX_OUTSTANDING_WRITES
            ):
                assert not int(self.dut.id_pool.alloc_valid.value), (
                    f"{descriptor.name}: all external ID users are occupied, "
                    "but the ID pool still reports an allocatable ID"
                )
                return

        raise AssertionError(
            f"{descriptor.name}: DMA did not consume all ID slots; "
            f"read_outstanding={self.read_target.outstanding} "
            f"write_outstanding={self.write_target.outstanding}"
        )

    async def run_descriptor(self, descriptor, expect_out_of_order=False):
        self.reset_bus_activity()
        before = self.snapshot_bus_activity()
        self.memory.load_random(
            descriptor.src_addr,
            descriptor.length_words,
            descriptor.seed,
        )

        await self.csr.program_descriptor(descriptor)
        timeout_cycles = max(1000, descriptor.length_words * 40 + 200)
        status = await self.csr.wait_done(
            use_interrupt=descriptor.irq_en,
            timeout_cycles=timeout_cycles,
        )
        status_fields = self.csr.status.decode(status)

        assert status_fields["done"], (
            f"{descriptor.name}: done bit not set: status=0x{status:08x}"
        )
        assert not status_fields["error"], (
            f"{descriptor.name}: unexpected error bit: status=0x{status:08x}"
        )
        assert not status_fields["busy"], (
            f"{descriptor.name}: busy bit still set at completion: status=0x{status:08x}"
        )

        after = self.snapshot_bus_activity()
        if descriptor.length_words == 0:
            self.check_zero_length_activity(before, after)
        else:
            self.check_copy(descriptor)

        if expect_out_of_order:
            self.check_out_of_order_activity(descriptor, before)

        await self.csr.clear_done()
        status = await self.csr.read_status()
        status_fields = self.csr.status.decode(status)
        assert not status_fields["done"], f"{descriptor.name}: done bit did not clear"

    async def run_id_exhaustion_descriptor(self, descriptor):
        self.reset_bus_activity()
        before = self.snapshot_bus_activity()
        self.memory.load_random(
            descriptor.src_addr,
            descriptor.length_words,
            descriptor.seed,
        )

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
            read_policy.response_delay = lambda _req, _sequence: 5
            read_policy.response_latency = 0
            read_policy.out_of_order_response = False
            write_policy.response_delay = lambda _req, _sequence: 200
            write_policy.response_latency = 0
            write_policy.out_of_order_response = False

            await self.csr.program_descriptor(descriptor)
            await self.wait_all_ids_in_use(descriptor)

            timeout_cycles = descriptor.length_words * 80 + 1000
            status = await self.csr.wait_done(
                use_interrupt=descriptor.irq_en,
                timeout_cycles=timeout_cycles,
            )
            status_fields = self.csr.status.decode(status)
            assert status_fields["done"], (
                f"{descriptor.name}: done bit not set: status=0x{status:08x}"
            )
            assert not status_fields["error"], (
                f"{descriptor.name}: unexpected error bit: status=0x{status:08x}"
            )
            assert not status_fields["busy"], (
                f"{descriptor.name}: busy bit still set at completion: status=0x{status:08x}"
            )

            self.check_copy(descriptor)
            after = self.snapshot_bus_activity()
            assert after["read_accepted"] > before["read_accepted"], (
                f"{descriptor.name}: no read requests accepted"
            )
            assert after["write_accepted"] > before["write_accepted"], (
                f"{descriptor.name}: no write requests accepted"
            )
            assert self.read_target.max_outstanding >= MAX_OUTSTANDING_READS, (
                f"{descriptor.name}: expected {MAX_OUTSTANDING_READS} outstanding reads, "
                f"saw {self.read_target.max_outstanding}"
            )
            assert self.write_target.max_outstanding >= MAX_OUTSTANDING_WRITES, (
                f"{descriptor.name}: expected {MAX_OUTSTANDING_WRITES} outstanding writes, "
                f"saw {self.write_target.max_outstanding}"
            )

            await self.csr.clear_done()
            status = await self.csr.read_status()
            status_fields = self.csr.status.decode(status)
            assert not status_fields["done"], f"{descriptor.name}: done bit did not clear"
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

    async def run_busy_csr_write_error_test(self, descriptor):
        self.reset_bus_activity()
        self.memory.load_random(
            descriptor.src_addr,
            descriptor.length_words,
            descriptor.seed,
        )

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
            read_policy.response_delay = lambda _req, _sequence: 20
            read_policy.response_latency = 0
            read_policy.out_of_order_response = False
            write_policy.response_delay = lambda _req, _sequence: 20
            write_policy.response_latency = 0
            write_policy.out_of_order_response = False

            await self.csr.program_descriptor(descriptor)

            for _ in range(200):
                status = await self.csr.read_status()
                status_fields = self.csr.status.decode(status)
                if status_fields["busy"]:
                    break
            else:
                raise AssertionError(f"{descriptor.name}: DMA did not enter busy state")

            protected_writes = [
                (self.csr.src_addr, descriptor.src_addr ^ 0x40),
                (self.csr.dst_addr, descriptor.dst_addr ^ 0x40),
                (self.csr.len_words, descriptor.length_words + 1),
            ]

            for reg, data in protected_writes:
                await self.csr.frontdoor.write(reg, data)
                status = await self.csr.read_status()
                status_fields = self.csr.status.decode(status)
                assert status_fields["error"], (
                    f"{descriptor.name}: busy write to {reg.path} did not set error: "
                    f"status=0x{status:08x}"
                )
                assert status_fields["busy"], (
                    f"{descriptor.name}: DMA stopped after busy write to {reg.path}: "
                    f"status=0x{status:08x}"
                )
                await self.csr.clear_error()

            timeout_cycles = descriptor.length_words * 80 + 1000
            status = await self.csr.wait_done(
                use_interrupt=descriptor.irq_en,
                timeout_cycles=timeout_cycles,
            )
            status_fields = self.csr.status.decode(status)
            assert status_fields["done"], (
                f"{descriptor.name}: done bit not set: status=0x{status:08x}"
            )
            assert not status_fields["error"], (
                f"{descriptor.name}: error bit remained set: status=0x{status:08x}"
            )
            assert not status_fields["busy"], (
                f"{descriptor.name}: busy bit still set at completion: status=0x{status:08x}"
            )
            self.check_copy(descriptor)

            await self.csr.clear_done()
            status = await self.csr.read_status()
            status_fields = self.csr.status.decode(status)
            assert not status_fields["done"], f"{descriptor.name}: done bit did not clear"
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

    async def run_illegal_descriptor(self, descriptor):
        self.reset_bus_activity()
        before = self.snapshot_bus_activity()

        await self.csr.frontdoor.write(self.csr.src_addr, descriptor.src_addr)
        await self.csr.frontdoor.write(self.csr.dst_addr, descriptor.dst_addr)
        await self.csr.frontdoor.write(self.csr.len_words, descriptor.length_words)
        status = await self.csr.read_status()
        status_fields = self.csr.status.decode(status)
        assert not status_fields["error"], (
            f"{descriptor.name}: descriptor validation happened before CTRL.start: "
            f"status=0x{status:08x}"
        )

        ctrl = self.csr.ctrl.encode(start=1, irq_en=int(descriptor.irq_en))
        await self.csr.frontdoor.write(self.csr.ctrl, ctrl)
        await ClockCycles(self.dut.clk, 4)
        status = await self.csr.read_status()
        status_fields = self.csr.status.decode(status)

        assert status_fields["error"], (
            f"{descriptor.name}: error bit not set for illegal descriptor: "
            f"status=0x{status:08x}"
        )
        assert int(self.dut.irq_error.value) == int(descriptor.irq_en), (
            f"{descriptor.name}: irq_error mismatch for irq_en={descriptor.irq_en}"
        )
        assert not status_fields["busy"], (
            f"{descriptor.name}: busy bit set for rejected descriptor: "
            f"status=0x{status:08x}"
        )
        assert not status_fields["done"], (
            f"{descriptor.name}: done bit set for rejected descriptor: "
            f"status=0x{status:08x}"
        )

        after = self.snapshot_bus_activity()
        self.check_zero_length_activity(before, after)

        await self.csr.clear_error()
        status = await self.csr.read_status()
        status_fields = self.csr.status.decode(status)
        assert not status_fields["error"], f"{descriptor.name}: error bit did not clear"
        assert not int(self.dut.irq_error.value), (
            f"{descriptor.name}: irq_error did not clear after STATUS.error W1C"
        )


@cocotb.test()
async def dma_descriptor_size_suite(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    env = DmaEnv(dut)
    await env.start()
    await env.reset()
    await env.csr.run_common_access_tests()
    await env.csr.run_invalid_access_tests()
    await env.reset()

    descriptors = [
        DmaDescriptor("zero_words", 0x0000, 0x1000, 0, 0xD000_0000),
        DmaDescriptor("one_word", 0x0100, 0x1100, 1, 0xD100_0000),
        DmaDescriptor(
            "max_writes_words",
            0x0200,
            0x1200,
            MAX_OUTSTANDING_WRITES,
            0xD200_0000,
        ),
        DmaDescriptor(
            "max_reads_words",
            0x0300,
            0x1300,
            MAX_OUTSTANDING_READS,
            0xD300_0000,
        ),
        DmaDescriptor("slot_count_words", 0x0400, 0x1400, SLOT_COUNT, 0xD400_0000),
        DmaDescriptor("out_of_order_stress", 0x0500, 0x1500, 16, 0xD500_0000),
        DmaDescriptor("adjacent_ranges", 0x6000, 0x6020, 8, 0xD580_0000),
        DmaDescriptor(
            "max_transfer_q0_to_q2",
            0x0000,
            0x8000,
            MAX_TRANSFER_WORDS,
            0xD600_0000,
        ),
        DmaDescriptor(
            "max_transfer_q1_to_q3",
            0x4000,
            0xC000,
            MAX_TRANSFER_WORDS,
            0xD600_0001,
        ),
        DmaDescriptor(
            "max_transfer_q2_to_q0",
            0x8000,
            0x0000,
            MAX_TRANSFER_WORDS,
            0xD600_0002,
        ),
        DmaDescriptor(
            "max_transfer_q3_to_q1",
            0xC000,
            0x4000,
            MAX_TRANSFER_WORDS,
            0xD600_0003,
        ),
    ]

    for descriptor in descriptors:
        await env.run_descriptor(
            descriptor,
            expect_out_of_order=descriptor.length_words >= 16,
        )

    await env.run_id_exhaustion_descriptor(
        DmaDescriptor(
            "id_exhaustion_long_response_delay",
            0x1800,
            0x9800,
            32,
            0xD800_0000,
        )
    )

    await env.run_busy_csr_write_error_test(
        DmaDescriptor(
            "busy_csr_write_error",
            0x2800,
            0xA800,
            64,
            0xD900_0000,
        )
    )

    illegal_descriptors = [
        DmaDescriptor(
            "over_max_transfer_words",
            0x3000,
            0x9000,
            MAX_TRANSFER_WORDS + 1,
            0xD700_0000,
        ),
        DmaDescriptor(
            "overlap_same_start",
            0x3400,
            0x3400,
            8,
            0xD710_0000,
        ),
        DmaDescriptor(
            "overlap_dst_inside_src",
            0x3800,
            0x3810,
            16,
            0xD720_0000,
        ),
        DmaDescriptor(
            "overlap_src_inside_dst",
            0x3C10,
            0x3C00,
            16,
            0xD730_0000,
            irq_en=False,
        ),
    ]

    for descriptor in illegal_descriptors:
        await env.run_illegal_descriptor(descriptor)
