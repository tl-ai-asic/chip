from dataclasses import dataclass, replace

from cocotb.triggers import RisingEdge


READABLE_ACCESSES = {"rw", "ro", "w1c", "w0c", "w1s", "w0s"}
WRITABLE_ACCESSES = {"rw", "wo", "w1c", "w0c", "w1s", "w0s"}


@dataclass(frozen=True)
class CsrRegAccess:
    kind: str
    reg: object
    data: int = 0


@dataclass(frozen=True)
class CsrBusTransaction:
    kind: str
    addr: int
    data: int = 0


class CsrRegAdapter:
    def reg_to_bus(self, access):
        kind = access.kind.lower()
        if kind not in {"read", "write"}:
            raise ValueError(f"unsupported CSR access kind {access.kind}")

        data = access.data & access.reg.mask if kind == "write" else 0
        return CsrBusTransaction(kind=kind, addr=access.reg.addr, data=data)

    def bus_to_reg(self, access, bus_transaction, read_data=None):
        if bus_transaction.kind == "read":
            return replace(access, data=read_data & access.reg.mask)
        return access


class CsrInitiator:
    def __init__(
        self,
        clk,
        valid,
        write,
        addr,
        wdata,
        ready,
        rvalid,
        rdata,
    ):
        self.clk = clk
        self.valid = valid
        self.write = write
        self.addr = addr
        self.wdata = wdata
        self.ready = ready
        self.rvalid = rvalid
        self.rdata = rdata

    def idle(self):
        self.valid.value = 0
        self.write.value = 0
        self.addr.value = 0
        self.wdata.value = 0

    async def write_addr(self, addr, data):
        self.valid.value = 1
        self.write.value = 1
        self.addr.value = addr
        self.wdata.value = data

        while True:
            await RisingEdge(self.clk)
            if int(self.ready.value):
                break

        self.idle()

    async def read_addr(self, addr):
        self.valid.value = 1
        self.write.value = 0
        self.addr.value = addr
        self.wdata.value = 0

        while True:
            await RisingEdge(self.clk)
            if int(self.ready.value) and int(self.rvalid.value):
                data = int(self.rdata.value)
                break

        self.idle()
        return data

    async def write_reg(self, addr, data):
        await self.write_addr(addr, data)

    async def read_reg(self, addr):
        return await self.read_addr(addr)


class CsrRegFrontdoor:
    def __init__(self, bus, adapter=None):
        self.bus = bus
        self.adapter = adapter or CsrRegAdapter()

    async def execute(self, access):
        bus_transaction = self.adapter.reg_to_bus(access)
        if bus_transaction.kind == "write":
            await self.bus.write_addr(bus_transaction.addr, bus_transaction.data)
            return access

        read_data = await self.bus.read_addr(bus_transaction.addr)
        return self.adapter.bus_to_reg(access, bus_transaction, read_data)

    async def write(self, reg, data):
        await self.execute(CsrRegAccess("write", reg, data))

    async def read(self, reg):
        completed = await self.execute(CsrRegAccess("read", reg))
        return completed.data


class CsrMirror:
    def __init__(self, block):
        self.block = block
        self.values = {}
        self.reset()

    def reset(self):
        self.values = self.block.reset_values()

    def get(self, reg):
        return self.values.get(reg.addr, reg.reset_value()) & reg.mask

    def predict_write(self, reg, data):
        old_value = self.get(reg)
        new_value = self._predict_reg_write(reg, old_value, data & reg.mask)
        self.values[reg.addr] = new_value & reg.mask
        return self.values[reg.addr]

    def predict_read(self, reg):
        return self.get(reg)

    def _predict_reg_write(self, reg, old_value, data):
        if not reg.fields:
            return self._predict_access_write(reg.access, old_value, data, reg.mask)

        new_value = old_value
        for field in reg.fields.values():
            old_field = field.extract(old_value)
            data_field = field.extract(data)
            new_field = self._predict_access_write(
                field.access,
                old_field,
                data_field,
                field.mask_value,
            )
            new_value = field.insert(new_value, new_field)
        return new_value

    @staticmethod
    def _predict_access_write(access, old_value, data, mask):
        access = access.lower()
        data &= mask
        old_value &= mask

        if access == "rw":
            return data
        if access == "w1c":
            return old_value & ~data
        if access == "w0c":
            return old_value & data
        if access == "w1s":
            return old_value | data
        if access == "w0s":
            return old_value | (~data & mask)
        return old_value


class CsrCommonTester:
    def __init__(self, block, frontdoor, mirror=None):
        self.block = block
        self.frontdoor = frontdoor
        self.mirror = mirror or CsrMirror(block)

    async def check_reset(self, reset_cb=None):
        if reset_cb is not None:
            await reset_cb()
        self.mirror.reset()
        await self.check_all_readable("reset")

    async def check_read_write_access(self):
        for reg in self.block.iter_regs():
            for data in self.write_data_for_reg(reg):
                await self.frontdoor.write(reg, data)
                self.mirror.predict_write(reg, data)
                await self.check_reg_readable(reg, f"write 0x{data:08x}")

    async def check_all_readable(self, phase):
        for reg in self.block.iter_regs():
            await self.check_reg_readable(reg, phase)

    async def check_reg_readable(self, reg, phase):
        compare_mask = self.compare_mask(reg)
        if compare_mask == 0:
            return

        actual = await self.frontdoor.read(reg)
        expected = self.mirror.predict_read(reg)
        if (actual ^ expected) & compare_mask:
            raise AssertionError(
                f"{reg.path} {phase}: expected 0x{expected & compare_mask:08x} "
                f"with mask 0x{compare_mask:08x}, got 0x{actual:08x}"
            )

    def compare_mask(self, reg):
        if reg.volatile or not reg.compare:
            return 0

        if not reg.fields:
            if reg.access.lower() not in READABLE_ACCESSES:
                return 0
            return reg.mask

        mask = 0
        for field in reg.fields.values():
            if field.volatile or not field.compare:
                continue
            if field.access.lower() in READABLE_ACCESSES:
                mask |= field.mask
        return mask & reg.mask

    def write_data_for_reg(self, reg):
        write_mask = self.write_test_mask(reg)
        if write_mask == 0:
            return []

        patterns = [
            0,
            write_mask,
            0xA5A5A5A5 & write_mask,
            0x5A5A5A5A & write_mask,
        ]

        unique_patterns = []
        for data in patterns:
            data &= reg.mask
            if data not in unique_patterns:
                unique_patterns.append(data)
        return unique_patterns

    def write_test_mask(self, reg):
        if reg.volatile or not reg.test:
            return 0

        if not reg.fields:
            if reg.access.lower() not in WRITABLE_ACCESSES:
                return 0
            return reg.mask

        mask = 0
        for field in reg.fields.values():
            if field.volatile or not field.test:
                continue
            if field.access.lower() in WRITABLE_ACCESSES:
                mask |= field.mask
        return mask & reg.mask
