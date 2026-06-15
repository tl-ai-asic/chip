import os
import re
import struct
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


RESET_VECTOR = int(os.getenv("RESET_VECTOR", "0x80000000"), 0)
DEFAULT_TOHOST = RESET_VECTOR + 0x1000
CORE_VERSION = os.getenv("CORE_VERSION", "v4")
EXPECT_LSU_PARALLEL = int(os.getenv("EXPECT_LSU_PARALLEL", "0"), 0) != 0
IPC_BENCHMARK_FILES = {
    "back_to_back_basic_rv32i_alu_ops": "ipc_alu",
    "back_to_back_multiply_divide_ops": "ipc_muldiv",
    "back_to_back_load_store_ops": "ipc_load_store",
    "parallel_alu_lsu_muldiv_ops": "ipc_parallel",
    "branch_loop_prefetch_ops": "ipc_branch_loops",
    "random_500_instruction_mix": "ipc_random",
}


def env_or_default(name, default=None):
    value = os.getenv(name)
    return default if value in (None, "") else value


def _bits(value, width):
    return value & ((1 << width) - 1)


def enc_i(imm, rs1, funct3, rd, opcode):
    return (_bits(imm, 12) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return (
        (funct7 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def enc_s(imm, rs2, rs1, funct3, opcode=0x23):
    imm = _bits(imm, 12)
    return (
        ((imm >> 5) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | ((imm & 0x1F) << 7)
        | opcode
    )


def enc_b(imm, rs2, rs1, funct3, opcode=0x63):
    imm = _bits(imm, 13)
    return (
        ((imm >> 12) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 0x1) << 7)
        | opcode
    )


def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(imm, rd, opcode=0x6F):
    imm = _bits(imm, 21)
    return (
        ((imm >> 20) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 0x1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | (rd << 7)
        | opcode
    )


def addi(rd, rs1, imm):
    return enc_i(imm, rs1, 0x0, rd, 0x13)


def add(rd, rs1, rs2):
    return enc_r(0x00, rs2, rs1, 0x0, rd)


def lui(rd, imm20):
    return enc_u(imm20, rd, 0x37)


def lw(rd, imm, rs1):
    return enc_i(imm, rs1, 0x2, rd, 0x03)


def sw(rs2, imm, rs1):
    return enc_s(imm, rs2, rs1, 0x2)


def bne(rs1, rs2, imm):
    return enc_b(imm, rs2, rs1, 0x1)


def jal(rd, imm):
    return enc_j(imm, rd)


def mul(rd, rs1, rs2):
    return enc_r(0x01, rs2, rs1, 0x0, rd)


def mulhu(rd, rs1, rs2):
    return enc_r(0x01, rs2, rs1, 0x3, rd)


def div(rd, rs1, rs2):
    return enc_r(0x01, rs2, rs1, 0x4, rd)


def divu(rd, rs1, rs2):
    return enc_r(0x01, rs2, rs1, 0x5, rd)


def rem(rd, rs1, rs2):
    return enc_r(0x01, rs2, rs1, 0x6, rd)


def remu(rd, rs1, rs2):
    return enc_r(0x01, rs2, rs1, 0x7, rd)


class SparseMemory:
    def __init__(self):
        self.bytes = {}
        self.tohost_addr = None
        self.tohost_value = 0

    def clear(self):
        self.bytes.clear()
        self.tohost_addr = None
        self.tohost_value = 0

    def load_bytes(self, base_addr, data):
        for offset, byte in enumerate(data):
            self.bytes[base_addr + offset] = byte

    def load_words(self, base_addr, words):
        for index, word in enumerate(words):
            self.load_bytes(base_addr + index * 4, struct.pack("<I", word & 0xFFFFFFFF))

    def read_word(self, addr):
        base = addr & ~0x3
        value = 0
        for lane in range(4):
            value |= self.bytes.get(base + lane, 0) << (8 * lane)
        return value

    def write_word_lanes(self, addr, data, wstrb):
        base = addr & ~0x3
        for lane in range(4):
            if (wstrb >> lane) & 1:
                self.bytes[base + lane] = (data >> (8 * lane)) & 0xFF

        if self.tohost_addr is not None:
            self.tohost_value = self.read_word(self.tohost_addr)


def _read_c_string(blob, offset):
    end = blob.find(b"\x00", offset)
    if end < 0:
        return ""
    return blob[offset:end].decode("ascii", errors="replace")


def load_elf(memory, path):
    data = Path(path).read_bytes()
    if data[:4] != b"\x7fELF":
        raise ValueError(f"{path} is not an ELF file")
    if data[4] != 1 or data[5] != 1:
        raise ValueError("only ELF32 little-endian images are supported")

    entry = struct.unpack_from("<I", data, 24)[0]
    phoff = struct.unpack_from("<I", data, 28)[0]
    shoff = struct.unpack_from("<I", data, 32)[0]
    phentsize = struct.unpack_from("<H", data, 42)[0]
    phnum = struct.unpack_from("<H", data, 44)[0]
    shentsize = struct.unpack_from("<H", data, 46)[0]
    shnum = struct.unpack_from("<H", data, 48)[0]

    for index in range(phnum):
        offset = phoff + index * phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz = struct.unpack_from(
            "<IIIIII", data, offset
        )
        if p_type != 1:
            continue
        load_addr = p_paddr or p_vaddr
        segment = data[p_offset : p_offset + p_filesz]
        memory.load_bytes(load_addr, segment)
        if p_memsz > p_filesz:
            memory.load_bytes(load_addr + p_filesz, bytes(p_memsz - p_filesz))

    symbols = {}
    sections = []
    for index in range(shnum):
        offset = shoff + index * shentsize
        sections.append(struct.unpack_from("<IIIIIIIIII", data, offset))

    for section in sections:
        _name, sh_type, _flags, _addr, sh_offset, sh_size, sh_link, _info, _align, sh_entsize = section
        if sh_type not in (2, 11) or sh_entsize == 0 or sh_link >= len(sections):
            continue
        strtab = sections[sh_link]
        strtab_data = data[strtab[4] : strtab[4] + strtab[5]]
        for offset in range(sh_offset, sh_offset + sh_size, sh_entsize):
            st_name, st_value, _st_size, _st_info, _st_other, _st_shndx = struct.unpack_from(
                "<IIIBBH", data, offset
            )
            if st_name:
                symbols[_read_c_string(strtab_data, st_name)] = st_value

    return entry, symbols


def load_program(memory, image_path, base_addr=RESET_VECTOR):
    image_path = Path(image_path)
    data = image_path.read_bytes()
    if data[:4] == b"\x7fELF":
        return load_elf(memory, image_path)

    memory.load_bytes(base_addr, data)
    return base_addr, {}


class InstructionMemoryTarget:
    def __init__(self, dut, memory, response_latency=1):
        self.dut = dut
        self.memory = memory
        self.response_latency = response_latency
        self.pending = []

    def idle(self):
        self.dut.imem_req_ready.value = 0
        self.dut.imem_rsp_valid.value = 0
        self.dut.imem_rsp_rdata.value = 0
        self.dut.imem_rsp_err.value = 0

    async def run(self):
        self.idle()
        while True:
            await RisingEdge(self.dut.clk)
            if not int(self.dut.rst_n.value):
                self.pending.clear()
                self.idle()
                continue

            self.dut.imem_req_ready.value = 1
            self.dut.imem_rsp_valid.value = 0
            self.dut.imem_rsp_err.value = 0

            self.pending = [(delay - 1, addr) for delay, addr in self.pending]
            if self.pending and self.pending[0][0] <= 0:
                _, addr = self.pending.pop(0)
                self.dut.imem_rsp_valid.value = 1
                self.dut.imem_rsp_rdata.value = self.memory.read_word(addr)

            if int(self.dut.imem_req_valid.value) and int(self.dut.imem_req_ready.value):
                self.pending.append((self.response_latency, int(self.dut.imem_req_addr.value)))


class DataMemoryTarget:
    def __init__(self, dut, memory, response_latency=0):
        self.dut = dut
        self.memory = memory
        self.response_latency = response_latency
        self.pending = []

    def idle(self):
        self.dut.dmem_req_ready.value = 0
        self.dut.dmem_rsp_valid.value = 0
        self.dut.dmem_rsp_rdata.value = 0
        self.dut.dmem_rsp_err.value = 0

    async def run(self):
        self.idle()
        while True:
            await RisingEdge(self.dut.clk)
            if not int(self.dut.rst_n.value):
                self.pending.clear()
                self.idle()
                continue

            self.dut.dmem_req_ready.value = 1
            self.dut.dmem_rsp_valid.value = 0
            self.dut.dmem_rsp_err.value = 0

            self.pending = [(delay - 1, data) for delay, data in self.pending]
            if self.pending and self.pending[0][0] <= 0:
                _, data = self.pending.pop(0)
                self.dut.dmem_rsp_valid.value = 1
                self.dut.dmem_rsp_rdata.value = data

            if int(self.dut.dmem_req_valid.value) and int(self.dut.dmem_req_ready.value):
                addr = int(self.dut.dmem_req_addr.value)
                if int(self.dut.dmem_req_write.value):
                    self.memory.write_word_lanes(
                        addr,
                        int(self.dut.dmem_req_wdata.value),
                        int(self.dut.dmem_req_wstrb.value),
                    )
                    self.pending.append((self.response_latency, 0))
                else:
                    self.pending.append((self.response_latency, self.memory.read_word(addr)))


class CoreEnv:
    def __init__(self, dut, data_response_latency=0, imem_response_latency=1):
        self.dut = dut
        self.memory = SparseMemory()
        self.imem = InstructionMemoryTarget(dut, self.memory, imem_response_latency)
        self.dmem = DataMemoryTarget(dut, self.memory, data_response_latency)
        self._started = False

    async def start(self):
        if self._started:
            return
        cocotb.start_soon(Clock(self.dut.clk, 10, unit="ns").start())
        cocotb.start_soon(self.imem.run())
        cocotb.start_soon(self.dmem.run())
        self._started = True

    async def reset(self):
        self.dut.rst_n.value = 0
        self.imem.idle()
        self.dmem.idle()
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)

    async def run_until_tohost(self, timeout_cycles=20000):
        history = []
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if int(self.dut.rvfi_valid.value):
                history.append(
                    {
                        "pc": int(self.dut.rvfi_pc_rdata.value),
                        "insn": int(self.dut.rvfi_insn.value),
                        "rs1": int(self.dut.rvfi_rs1_addr.value),
                        "rs1_data": int(self.dut.rvfi_rs1_rdata.value),
                        "rs2": int(self.dut.rvfi_rs2_addr.value),
                        "rs2_data": int(self.dut.rvfi_rs2_rdata.value),
                        "rd": int(self.dut.rvfi_rd_addr.value),
                        "rd_data": int(self.dut.rvfi_rd_wdata.value),
                        "pc_next": int(self.dut.rvfi_pc_wdata.value),
                    }
                )
                history = history[-16:]
            if self.memory.tohost_value:
                value = self.memory.tohost_value
                if value != 1:
                    for item in history:
                        self.dut._log.error(
                            "rvfi pc=0x%08x insn=0x%08x rs1=x%d/0x%08x "
                            "rs2=x%d/0x%08x rd=x%d/0x%08x next=0x%08x",
                            item["pc"],
                            item["insn"],
                            item["rs1"],
                            item["rs1_data"],
                            item["rs2"],
                            item["rs2_data"],
                            item["rd"],
                            item["rd_data"],
                            item["pc_next"],
                        )
                assert value == 1, f"riscv-test failed: tohost=0x{value:08x}"
                return

        pc = int(self.dut.rvfi_pc_rdata.value) if int(self.dut.rvfi_valid.value) else 0
        raise TimeoutError(f"program did not write tohost before timeout; last_pc=0x{pc:08x}")


def build_smoke_program(tohost_addr):
    hi20 = (tohost_addr + 0x800) >> 12
    lo12 = tohost_addr - (hi20 << 12)

    return [
        addi(1, 0, 6),          # x1 = 6
        addi(2, 0, 7),          # x2 = 7
        mul(3, 1, 2),           # x3 = 42
        addi(4, 0, 42),         # x4 = 42
        bne(3, 4, 24),          # branch to fail if multiply is wrong
        lui(5, hi20),           # x5 = tohost high bits
        addi(5, 5, lo12),       # x5 = tohost
        addi(6, 0, 1),          # pass value
        sw(6, 0, 5),            # write tohost = 1
        jal(0, 0),              # loop
        lui(5, hi20),           # fail path
        addi(5, 5, lo12),
        addi(6, 0, 3),
        sw(6, 0, 5),
        jal(0, 0),
    ]


def build_lsu_parallel_load_program(data_addr, tohost_addr):
    data_hi20 = (data_addr + 0x800) >> 12
    data_lo12 = data_addr - (data_hi20 << 12)
    tohost_hi20 = (tohost_addr + 0x800) >> 12
    tohost_lo12 = tohost_addr - (tohost_hi20 << 12)

    return [
        lui(1, data_hi20),        # x1 = data base high bits
        addi(1, 1, data_lo12),    # x1 = data base
        lw(2, 0, 1),              # x2 = data[0]
        lw(3, 8, 1),              # x3 = data[2], independent of first load
        add(4, 2, 3),             # x4 = 42 after both loads retire
        addi(5, 0, 42),           # expected sum
        bne(4, 5, 24),            # branch to fail if load data is wrong
        lui(6, tohost_hi20),      # pass path
        addi(6, 6, tohost_lo12),
        addi(7, 0, 1),
        sw(7, 0, 6),
        jal(0, 0),
        lui(6, tohost_hi20),      # fail path
        addi(6, 6, tohost_lo12),
        addi(7, 0, 3),
        sw(7, 0, 6),
        jal(0, 0),
    ]


def build_li(rd, value):
    hi20 = (value + 0x800) >> 12
    lo12 = value - (hi20 << 12)
    return [lui(rd, hi20), addi(rd, rd, lo12)]


def build_pass_program(tohost_addr):
    program = []
    program.extend(build_li(1, tohost_addr))
    program.append(addi(2, 0, 1))
    program.append(sw(2, 0, 1))
    program.append(jal(0, 0))
    return program


def _alu_sources(index):
    src_regs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    return src_regs[index % len(src_regs)], src_regs[(index + 3) % len(src_regs)]


def _alu_dest(index):
    return 11 + (index % 21)


def build_ipc_alu_program():
    setup = []
    for reg in range(1, 11):
        setup.append(addi(reg, 0, reg + 3))

    ops = []
    builders = [
        lambda rd, rs1, rs2: add(rd, rs1, rs2),
        lambda rd, rs1, rs2: enc_r(0x20, rs2, rs1, 0x0, rd),  # sub
        lambda rd, rs1, rs2: enc_r(0x00, rs2, rs1, 0x4, rd),  # xor
        lambda rd, rs1, rs2: enc_r(0x00, rs2, rs1, 0x6, rd),  # or
        lambda rd, rs1, rs2: enc_r(0x00, rs2, rs1, 0x7, rd),  # and
        lambda rd, rs1, rs2: enc_r(0x00, rs2, rs1, 0x2, rd),  # slt
        lambda rd, rs1, rs2: enc_r(0x00, rs2, rs1, 0x3, rd),  # sltu
    ]
    for index in range(500):
        rs1, rs2 = _alu_sources(index)
        ops.append(builders[index % len(builders)](_alu_dest(index), rs1, rs2))
    return setup, ops, {}


def build_ipc_muldiv_program():
    setup = []
    for reg in range(1, 11):
        setup.append(addi(reg, 0, reg + 17))

    ops = []
    builders = [mul, mulhu, div, divu, rem, remu]
    for index in range(500):
        rs1, rs2 = _alu_sources(index)
        ops.append(builders[index % len(builders)](_alu_dest(index), rs1, rs2))
    return setup, ops, {}


def build_ipc_load_store_program(data_addr):
    setup = []
    base_regs = list(range(1, 11))
    for offset, reg in enumerate(base_regs):
        setup.extend(build_li(reg, data_addr + offset * 0x400))
    for reg in range(11, 21):
        setup.append(addi(reg, 0, reg + 23))

    ops = []
    data_words = {}
    load_dests = list(range(21, 32))
    store_sources = list(range(11, 21))
    for index in range(500):
        base_index = index % len(base_regs)
        base = base_regs[base_index]
        offset = ((index // len(base_regs)) * 4) & 0x7FF
        addr = data_addr + base_index * 0x400 + offset
        if index % 2 == 0:
            data_words[addr] = 0x1000 + index
            ops.append(lw(load_dests[index % len(load_dests)], offset, base))
        else:
            ops.append(sw(store_sources[index % len(store_sources)], offset, base))
    return setup, ops, data_words


def build_ipc_parallel_program(data_addr):
    setup = []
    for reg, value in [(1, data_addr), (6, data_addr + 0x400), (7, 19), (8, 23), (9, 29), (10, 31)]:
        if value >= 0x1000:
            setup.extend(build_li(reg, value))
        else:
            setup.append(addi(reg, 0, value))
    for reg in range(2, 6):
        setup.append(addi(reg, 0, reg + 11))

    ops = []
    data_words = {}
    alu_dests = [11, 12, 13, 14, 15]
    mul_dests = [16, 17, 18, 19, 20]
    load_dests = list(range(21, 32))
    for group in range(125):
        load_offset = (group * 4) & 0x7FF
        store_offset = ((group * 4) + 0x80) & 0x7FF
        data_words[data_addr + load_offset] = 0x2000 + group
        ops.append(add(alu_dests[group % len(alu_dests)], 2 + (group % 4), 2 + ((group + 1) % 4)))
        ops.append(lw(load_dests[group % len(load_dests)], load_offset, 1))
        ops.append(mul(mul_dests[group % len(mul_dests)], 7 + (group % 4), 7 + ((group + 1) % 4)))
        ops.append(sw(2 + (group % 4), store_offset, 6))
    return setup, ops, data_words


def ipc_benchmark_path(name):
    binary_name = IPC_BENCHMARK_FILES[name]
    explicit_binaries = os.getenv("IPC_BINARIES", "")
    for item in re.split(r"[:,\s]+", explicit_binaries):
        if item and Path(item).name == binary_name:
            return Path(item)
    binary_dir = Path(env_or_default("IPC_BINARY_DIR", "/tmp/riscv32imc_ipc_benchmarks"))
    return binary_dir / binary_name


async def run_ipc_program(dut, name, data_response_latency=2, imem_response_latency=2):
    binary_path = ipc_benchmark_path(name)
    assert binary_path.exists(), f"{name} benchmark binary not found: {binary_path}"
    env = CoreEnv(dut, data_response_latency=data_response_latency, imem_response_latency=imem_response_latency)
    await env.start()

    env.memory.clear()
    entry, symbols = load_program(env.memory, binary_path)
    missing = [symbol for symbol in ("workload_start", "workload_end", "tohost") if symbol not in symbols]
    assert not missing, f"{binary_path} missing required symbols: {', '.join(missing)}"
    if entry != RESET_VECTOR:
        dut._log.warning(
            "%s entry is 0x%08x but RESET_VECTOR parameter is 0x%08x",
            binary_path,
            entry,
            RESET_VECTOR,
        )
    workload_start_pc = symbols["workload_start"]
    workload_end_pc = symbols["workload_end"]
    assert workload_start_pc % 4 == 0 and workload_end_pc % 4 == 0
    static_workload_instructions = (workload_end_pc - workload_start_pc) // 4
    workload_instructions = symbols.get("workload_expected_retired", static_workload_instructions)
    assert workload_instructions > 0, f"{name} must retire at least one workload instruction"
    if "workload_expected_retired" not in symbols:
        assert static_workload_instructions == 500, f"{name} must contain exactly 500 workload instructions"
    env.memory.tohost_addr = symbols["tohost"]

    await env.reset()

    workload_retired = 0
    active = False
    measured = False
    cycles = 0
    ipc = 0.0
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if active and not measured:
            cycles += 1

        if int(dut.rvfi_valid.value):
            pc = int(dut.rvfi_pc_rdata.value)
            if workload_start_pc <= pc < workload_end_pc:
                if not active:
                    active = True
                    cycles = 1
                workload_retired += 1
                if workload_retired == workload_instructions:
                    measured = True
                    ipc = workload_retired / cycles

        if env.memory.tohost_value:
            assert env.memory.tohost_value == 1, f"{name} failed: tohost=0x{env.memory.tohost_value:08x}"
            assert workload_retired == workload_instructions, f"{name} retired {workload_retired}/500 workload instructions"
            dut._log.info(
                "IPC_PERF core=%s test=%s instructions=%d cycles=%d ipc=%.4f",
                CORE_VERSION,
                name,
                workload_retired,
                cycles,
                ipc,
            )
            return ipc

    raise TimeoutError(f"{name} did not complete; retired {workload_retired}/500 workload instructions")


@cocotb.test()
async def test_rv32im_smoke_program(dut):
    env = CoreEnv(dut)
    await env.start()

    env.memory.clear()
    env.memory.tohost_addr = DEFAULT_TOHOST
    env.memory.load_words(RESET_VECTOR, build_smoke_program(DEFAULT_TOHOST))

    await env.reset()
    await env.run_until_tohost(timeout_cycles=500)

    retired = int(dut.rvfi_order.value)
    assert retired >= 8, f"expected at least 8 retired instructions, saw {retired}"


@cocotb.test()
async def test_lsu_accepts_independent_memory_ops_while_pending(dut):
    env = CoreEnv(dut, data_response_latency=12)
    await env.start()

    data_addr = RESET_VECTOR + 0x100
    env.memory.clear()
    env.memory.tohost_addr = DEFAULT_TOHOST
    env.memory.load_words(RESET_VECTOR, build_lsu_parallel_load_program(data_addr, DEFAULT_TOHOST))
    env.memory.load_words(data_addr, [11, 0, 31])

    await env.reset()

    max_lsu_pending = 0
    for _ in range(1000):
        await RisingEdge(dut.clk)
        try:
            max_lsu_pending = max(max_lsu_pending, int(dut.u_lsu.count_q.value))
        except AttributeError:
            max_lsu_pending = 0
        if env.memory.tohost_value:
            assert env.memory.tohost_value == 1, f"parallel LSU program failed: tohost=0x{env.memory.tohost_value:08x}"
            if EXPECT_LSU_PARALLEL:
                assert max_lsu_pending >= 2, f"expected two independent memory operations pending in the {CORE_VERSION} LSU"
            elif max_lsu_pending:
                assert max_lsu_pending <= 1, f"expected {CORE_VERSION} LSU to serialize memory ops"
            return

    raise TimeoutError("parallel LSU program did not write tohost before timeout")


@cocotb.test()
async def test_ipc_back_to_back_basic_rv32i_alu_ops(dut):
    await run_ipc_program(dut, "back_to_back_basic_rv32i_alu_ops")


@cocotb.test()
async def test_ipc_back_to_back_multiply_divide_ops(dut):
    await run_ipc_program(dut, "back_to_back_multiply_divide_ops")


@cocotb.test()
async def test_ipc_back_to_back_load_store_ops(dut):
    await run_ipc_program(dut, "back_to_back_load_store_ops")


@cocotb.test()
async def test_ipc_parallel_alu_lsu_muldiv_ops(dut):
    await run_ipc_program(dut, "parallel_alu_lsu_muldiv_ops")


@cocotb.test()
async def test_ipc_branch_loop_prefetch_ops(dut):
    await run_ipc_program(dut, "branch_loop_prefetch_ops")


@cocotb.test()
async def test_ipc_random_500_instruction_mix(dut):
    await run_ipc_program(dut, "random_500_instruction_mix")


@cocotb.test()
async def test_external_riscv_binaries(dut):
    binaries_env = os.getenv("RISCV_BINARIES") or os.getenv("RISCV_BINARY")
    if not binaries_env:
        dut._log.info("RISCV_BINARY/RISCV_BINARIES not set; external riscv-tests skipped")
        return

    binary_paths = [item for item in re.split(r"[:,\s]+", binaries_env) if item]
    timeout_cycles = int(env_or_default("RISCV_TIMEOUT_CYCLES", "200000"), 0)
    raw_base = int(env_or_default("RISCV_BINARY_BASE", str(RESET_VECTOR)), 0)
    explicit_tohost = env_or_default("RISCV_TOHOST")

    env = CoreEnv(dut)
    await env.start()

    for binary_path in binary_paths:
        env.memory.clear()
        entry, symbols = load_program(env.memory, binary_path, raw_base)
        tohost_addr = int(explicit_tohost, 0) if explicit_tohost else symbols.get("tohost")
        if tohost_addr is None:
            tohost_addr = DEFAULT_TOHOST
            dut._log.warning(
                "%s has no tohost symbol; using default 0x%08x",
                binary_path,
                tohost_addr,
            )
        if entry != RESET_VECTOR:
            dut._log.warning(
                "%s entry is 0x%08x but RESET_VECTOR parameter is 0x%08x",
                binary_path,
                entry,
                RESET_VECTOR,
            )

        env.memory.tohost_addr = tohost_addr
        await env.reset()
        dut._log.info("running %s with tohost=0x%08x", binary_path, tohost_addr)
        await env.run_until_tohost(timeout_cycles=timeout_cycles)
