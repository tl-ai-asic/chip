import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotbext.axi import (
    ApbBus,
    ApbRam,
    AxiBus,
    AxiBurstType,
    AxiLiteBus,
    AxiLiteMaster,
    AxiMaster,
    AxiRam,
    AxiResp,
)


AXI_BASE = 0x0000_0000
APB_BASE = 0x1000_0000
MISS_BASE = 0x2000_0000
DATA_WIDTH_BYTES = 4


class CrossbarEnv:
    def __init__(self, dut):
        self.dut = dut
        self.axi_master = AxiMaster(
            AxiBus.from_prefix(dut, "s_axi"),
            dut.clk,
            dut.rst_n,
            reset_active_level=False,
        )
        self.axil_master = AxiLiteMaster(
            AxiLiteBus.from_prefix(dut, "s_axil"),
            dut.clk,
            dut.rst_n,
            reset_active_level=False,
        )
        self.axi_ram = AxiRam(
            AxiBus.from_prefix(dut, "m_axi"),
            dut.clk,
            dut.rst_n,
            reset_active_level=False,
            size=0x1000,
        )
        self.apb_ram = ApbRam(
            ApbBus.from_prefix(dut, "m_apb"),
            dut.clk,
            dut.rst_n,
            reset_active_level=False,
            size=0x1000,
        )

    async def reset(self):
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)


async def init_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    env = CrossbarEnv(dut)
    await env.reset()
    return env


def check_resp(resp, expected, name):
    assert resp.resp == expected, f"{name} response was {resp.resp}, expected {expected}"


def apb_offset(addr):
    return addr & 0xFFF


@cocotb.test()
async def axi_upstream_routes_to_axi_downstream(dut):
    env = await init_dut(dut)
    addr = AXI_BASE + 0x40
    payload = bytes(range(32))

    write_resp = await env.axi_master.write(addr, payload, awid=3)
    check_resp(write_resp, AxiResp.OKAY, "AXI-to-AXI write")
    assert env.axi_ram.read(addr, len(payload)) == payload

    expected = bytes((0x80 + i) & 0xFF for i in range(24))
    env.axi_ram.write(addr + 0x80, expected)
    read_resp = await env.axi_master.read(addr + 0x80, len(expected), arid=5)
    check_resp(read_resp, AxiResp.OKAY, "AXI-to-AXI read")
    assert bytes(read_resp.data) == expected


@cocotb.test()
async def axil_upstream_routes_to_axi_downstream(dut):
    env = await init_dut(dut)
    addr = AXI_BASE + 0x120
    payload = b"\x11\x22\x33\x44"

    write_resp = await env.axil_master.write(addr, payload)
    check_resp(write_resp, AxiResp.OKAY, "AXI-Lite-to-AXI write")
    assert env.axi_ram.read(addr, len(payload)) == payload

    expected = b"\x99\x88\x77\x66"
    env.axi_ram.write(addr + 4, expected)
    read_resp = await env.axil_master.read(addr + 4, len(expected))
    check_resp(read_resp, AxiResp.OKAY, "AXI-Lite-to-AXI read")
    assert bytes(read_resp.data) == expected


@cocotb.test()
async def axi_upstream_routes_to_apb_downstream(dut):
    env = await init_dut(dut)
    addr = APB_BASE + 0x20
    payload = b"\x01\x23\x45\x67\x89\xab\xcd\xef"

    write_resp = await env.axi_master.write(
        addr,
        payload,
        awid=1,
        burst=AxiBurstType.INCR,
        size=2,
    )
    check_resp(write_resp, AxiResp.OKAY, "AXI-to-APB write")
    assert env.apb_ram.read(apb_offset(addr), len(payload)) == payload

    expected = b"\xfe\xdc\xba\x98\x76\x54\x32\x10"
    env.apb_ram.write(apb_offset(addr + 0x40), expected)
    read_resp = await env.axi_master.read(
        addr + 0x40,
        len(expected),
        arid=2,
        burst=AxiBurstType.INCR,
        size=2,
    )
    check_resp(read_resp, AxiResp.OKAY, "AXI-to-APB read")
    assert bytes(read_resp.data) == expected


@cocotb.test()
async def axil_upstream_routes_to_apb_downstream(dut):
    env = await init_dut(dut)
    addr = APB_BASE + 0x180
    payload = b"\xaa\xbb\xcc\xdd"

    write_resp = await env.axil_master.write(addr, payload)
    check_resp(write_resp, AxiResp.OKAY, "AXI-Lite-to-APB write")
    assert env.apb_ram.read(apb_offset(addr), len(payload)) == payload

    expected = b"\x12\x34\x56\x78"
    env.apb_ram.write(apb_offset(addr + DATA_WIDTH_BYTES), expected)
    read_resp = await env.axil_master.read(addr + DATA_WIDTH_BYTES, len(expected))
    check_resp(read_resp, AxiResp.OKAY, "AXI-Lite-to-APB read")
    assert bytes(read_resp.data) == expected


@cocotb.test()
async def decode_miss_returns_error_without_downstream_access(dut):
    env = await init_dut(dut)
    miss_addr = MISS_BASE + 0x44

    write_resp = await env.axil_master.write(miss_addr, b"\xde\xad\xbe\xef")
    check_resp(write_resp, AxiResp.DECERR, "AXI-Lite decode-miss write")

    read_resp = await env.axil_master.read(miss_addr, DATA_WIDTH_BYTES)
    check_resp(read_resp, AxiResp.DECERR, "AXI-Lite decode-miss read")
    assert bytes(read_resp.data) == b"\x00" * DATA_WIDTH_BYTES

    axi_write_resp = await env.axi_master.write(miss_addr + 0x40, b"\x01\x02\x03\x04", awid=7)
    check_resp(axi_write_resp, AxiResp.DECERR, "AXI decode-miss write")

    axi_read_resp = await env.axi_master.read(miss_addr + 0x80, 8, arid=6)
    check_resp(axi_read_resp, AxiResp.DECERR, "AXI decode-miss read")
    assert bytes(axi_read_resp.data) == b"\x00" * 8
