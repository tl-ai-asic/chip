import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


DATA_MASK = 0xFFFF_FFFF


def apply_wstrb(old, new, wstrb):
    value = old
    for byte in range(4):
        if (wstrb >> byte) & 1:
            mask = 0xFF << (byte * 8)
            value = (value & ~mask) | (new & mask)
    return value & DATA_MASK


class BackingMemory:
    def __init__(self, dut, response_latency=2):
        self.dut = dut
        self.response_latency = response_latency
        self.words = {}
        self.read_count = 0
        self.write_count = 0
        self.requests = []
        self.responses = []
        self.pending = []

    def idle(self):
        self.dut.mem_req_ready.value = 0
        self.dut.mem_rsp_valid.value = 0
        self.dut.mem_rsp_rdata.value = 0
        self.dut.mem_rsp_error.value = 0

    def read_word(self, addr):
        return self.words.get(addr, 0)

    def write_word(self, addr, data, wstrb):
        old = self.read_word(addr)
        self.words[addr] = apply_wstrb(old, data, wstrb)

    async def run(self):
        self.idle()
        while True:
            await RisingEdge(self.dut.clk)

            if not int(self.dut.rst_n.value):
                self.pending.clear()
                self.idle()
                continue

            self.dut.mem_req_ready.value = 1

            if int(self.dut.mem_req_valid.value) and int(self.dut.mem_req_ready.value):
                req = {
                    "write": int(self.dut.mem_req_write.value),
                    "addr": int(self.dut.mem_req_addr.value),
                    "wdata": int(self.dut.mem_req_wdata.value),
                    "wstrb": int(self.dut.mem_req_wstrb.value),
                }
                self.requests.append(req)

                if req["write"]:
                    self.write_count += 1
                    self.write_word(req["addr"], req["wdata"], req["wstrb"])
                    rsp = {"rdata": 0, "error": 0, "write": 1, "addr": req["addr"]}
                else:
                    self.read_count += 1
                    rsp = {
                        "rdata": self.read_word(req["addr"]),
                        "error": 0,
                        "write": 0,
                        "addr": req["addr"],
                    }

                self.pending.append({"delay": self.response_latency, "rsp": rsp})

            for item in self.pending:
                item["delay"] -= 1

            if int(self.dut.mem_rsp_valid.value):
                if int(self.dut.mem_rsp_ready.value):
                    self.responses.append(
                        {
                            "rdata": int(self.dut.mem_rsp_rdata.value),
                            "error": int(self.dut.mem_rsp_error.value),
                        }
                    )
                    self.dut.mem_rsp_valid.value = 0
                    self.dut.mem_rsp_rdata.value = 0
                    self.dut.mem_rsp_error.value = 0
                continue

            ready = [item for item in self.pending if item["delay"] <= 0]
            if ready:
                item = ready[0]
                self.pending.remove(item)
                rsp = item["rsp"]
                self.dut.mem_rsp_valid.value = 1
                self.dut.mem_rsp_rdata.value = rsp["rdata"]
                self.dut.mem_rsp_error.value = rsp["error"]


class CpuAgent:
    def __init__(self, dut):
        self.dut = dut

    def idle(self):
        self.dut.cpu_req_valid.value = 0
        self.dut.cpu_req_write.value = 0
        self.dut.cpu_req_addr.value = 0
        self.dut.cpu_req_wdata.value = 0
        self.dut.cpu_req_wstrb.value = 0
        self.dut.cpu_rsp_ready.value = 1

    async def request(self, write, addr, wdata=0, wstrb=0xF):
        self.dut.cpu_req_valid.value = 1
        self.dut.cpu_req_write.value = int(write)
        self.dut.cpu_req_addr.value = addr
        self.dut.cpu_req_wdata.value = wdata
        self.dut.cpu_req_wstrb.value = wstrb

        while True:
            await RisingEdge(self.dut.clk)
            if int(self.dut.cpu_req_ready.value):
                break

        self.dut.cpu_req_valid.value = 0
        self.dut.cpu_req_write.value = 0
        self.dut.cpu_req_addr.value = 0
        self.dut.cpu_req_wdata.value = 0
        self.dut.cpu_req_wstrb.value = 0

        for _ in range(100):
            await RisingEdge(self.dut.clk)
            if int(self.dut.cpu_rsp_valid.value):
                return {
                    "rdata": int(self.dut.cpu_rsp_rdata.value),
                    "hit": int(self.dut.cpu_rsp_hit.value),
                    "error": int(self.dut.cpu_rsp_error.value),
                }

        raise TimeoutError("CPU response timed out")

    async def read(self, addr):
        return await self.request(False, addr, 0, 0)

    async def write(self, addr, wdata, wstrb=0xF):
        return await self.request(True, addr, wdata, wstrb)


class CacheEnv:
    def __init__(self, dut):
        self.dut = dut
        self.cpu = CpuAgent(dut)
        self.memory = BackingMemory(dut)

    def idle(self):
        self.cpu.idle()
        self.memory.idle()

    async def start(self):
        cocotb.start_soon(self.memory.run())

    async def reset(self):
        self.idle()
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)


async def init_env(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    env = CacheEnv(dut)
    await env.start()
    await env.reset()
    return env


@cocotb.test()
async def read_miss_then_hit_uses_cached_data(dut):
    env = await init_env(dut)
    env.memory.words[0x0000] = 0x1122_3344

    rsp = await env.cpu.read(0x0000)
    assert rsp == {"rdata": 0x1122_3344, "hit": 0, "error": 0}
    assert env.memory.read_count == 1

    rsp = await env.cpu.read(0x0000)
    assert rsp == {"rdata": 0x1122_3344, "hit": 1, "error": 0}
    assert env.memory.read_count == 1


@cocotb.test()
async def write_hit_updates_cache_and_memory(dut):
    env = await init_env(dut)
    env.memory.words[0x0000] = 0x1122_3344

    rsp = await env.cpu.read(0x0000)
    assert rsp["hit"] == 0

    rsp = await env.cpu.write(0x0000, 0x0000_BEEF, wstrb=0x3)
    assert rsp == {"rdata": 0, "hit": 1, "error": 0}
    assert env.memory.read_word(0x0000) == 0x1122_BEEF

    rsp = await env.cpu.read(0x0000)
    assert rsp == {"rdata": 0x1122_BEEF, "hit": 1, "error": 0}
    assert env.memory.read_count == 1
    assert env.memory.write_count == 1


@cocotb.test()
async def write_miss_bypasses_without_allocate(dut):
    env = await init_env(dut)
    env.memory.words[0x0040] = 0xCAFE_BABE

    rsp = await env.cpu.write(0x0040, 0xDEAD_0000, wstrb=0xC)
    assert rsp == {"rdata": 0, "hit": 0, "error": 0}
    assert env.memory.read_word(0x0040) == 0xDEAD_BABE
    assert env.memory.write_count == 1

    rsp = await env.cpu.read(0x0040)
    assert rsp == {"rdata": 0xDEAD_BABE, "hit": 0, "error": 0}
    assert env.memory.read_count == 1


@cocotb.test()
async def lru_victim_is_least_recently_used_way(dut):
    env = await init_env(dut)

    addr_a = 0x0000
    addr_b = 0x0008
    addr_c = 0x0010
    env.memory.words[addr_a] = 0xAAAA_0001
    env.memory.words[addr_b] = 0xBBBB_0002
    env.memory.words[addr_c] = 0xCCCC_0003

    assert (await env.cpu.read(addr_a))["hit"] == 0
    assert (await env.cpu.read(addr_b))["hit"] == 0
    assert (await env.cpu.read(addr_a))["hit"] == 1

    read_count_before_c = env.memory.read_count
    assert (await env.cpu.read(addr_c))["hit"] == 0
    assert env.memory.read_count == read_count_before_c + 1

    assert (await env.cpu.read(addr_a))["hit"] == 1

    read_count_before_b = env.memory.read_count
    rsp = await env.cpu.read(addr_b)
    assert rsp == {"rdata": 0xBBBB_0002, "hit": 0, "error": 0}
    assert env.memory.read_count == read_count_before_b + 1
