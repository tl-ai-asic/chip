class CsrRegField:
    def __init__(
        self,
        name,
        lsb,
        width=1,
        access="rw",
        reset=0,
        description="",
        volatile=False,
        compare=True,
        test=True,
    ):
        if width <= 0:
            raise ValueError("field width must be greater than zero")
        if lsb < 0:
            raise ValueError("field lsb must be non-negative")

        self.name = name
        self.lsb = lsb
        self.width = width
        self.access = access
        self.reset = reset
        self.description = description
        self.volatile = volatile
        self.compare = compare
        self.test = test
        self.reg = None

        if reset & ~self.mask_value:
            raise ValueError(f"reset value for field {name} does not fit in {width} bits")

    @property
    def msb(self):
        return self.lsb + self.width - 1

    @property
    def mask_value(self):
        return (1 << self.width) - 1

    @property
    def mask(self):
        return self.mask_value << self.lsb

    @property
    def path(self):
        if self.reg is None:
            return self.name
        return f"{self.reg.path}.{self.name}"

    def extract(self, reg_value):
        return (reg_value >> self.lsb) & self.mask_value

    def insert(self, reg_value, field_value):
        if field_value & ~self.mask_value:
            raise ValueError(
                f"value 0x{field_value:x} does not fit in field {self.path}"
            )
        return (reg_value & ~self.mask) | ((field_value & self.mask_value) << self.lsb)

    def reset_bits(self):
        return self.reset << self.lsb


class CsrReg:
    def __init__(
        self,
        name,
        offset,
        width=32,
        access="rw",
        reset=0,
        description="",
        volatile=False,
        compare=True,
        test=True,
    ):
        if offset < 0:
            raise ValueError("register offset must be non-negative")
        if width <= 0:
            raise ValueError("register width must be greater than zero")

        self.name = name
        self.offset = offset
        self.width = width
        self.access = access
        self.reset = reset
        self.description = description
        self.volatile = volatile
        self.compare = compare
        self.test = test
        self.block = None
        self.fields = {}

        if reset & ~self.mask:
            raise ValueError(f"reset value for register {name} does not fit in {width} bits")

    @property
    def mask(self):
        return (1 << self.width) - 1

    @property
    def addr(self):
        if self.block is None:
            return self.offset
        return self.block.addr + self.offset

    @property
    def path(self):
        if self.block is None:
            return self.name
        return f"{self.block.path}.{self.name}"

    def add_field(self, field):
        if field.name in self.fields:
            raise ValueError(f"duplicate field {field.name} in register {self.path}")
        if field.msb >= self.width:
            raise ValueError(f"field {field.name} exceeds register width")
        for existing in self.fields.values():
            if field.mask & existing.mask:
                raise ValueError(
                    f"field {field.name} overlaps {existing.name} in register {self.path}"
                )

        field.reg = self
        self.fields[field.name] = field
        return field

    def field(self, name):
        return self.fields[name]

    def reset_value(self):
        value = self.reset
        for field in self.fields.values():
            value = field.insert(value, field.reset)
        return value & self.mask

    def encode(self, **field_values):
        value = self.reset_value()
        for name, field_value in field_values.items():
            value = self.field(name).insert(value, field_value)
        return value

    def decode(self, reg_value):
        return {name: field.extract(reg_value) for name, field in self.fields.items()}


class CsrBlock:
    def __init__(self, name, base_addr=0, description=""):
        if base_addr < 0:
            raise ValueError("block base address must be non-negative")

        self.name = name
        self.base_addr = base_addr
        self.description = description
        self.parent = None
        self.regs = {}
        self.blocks = {}

    @property
    def addr(self):
        if self.parent is None:
            return self.base_addr
        return self.parent.addr + self.base_addr

    @property
    def path(self):
        if self.parent is None:
            return self.name
        return f"{self.parent.path}.{self.name}"

    def add_reg(self, reg):
        if reg.name in self.regs:
            raise ValueError(f"duplicate register {reg.name} in block {self.path}")
        for existing in self.regs.values():
            if reg.offset == existing.offset:
                raise ValueError(
                    f"register {reg.name} shares offset 0x{reg.offset:x} "
                    f"with {existing.name} in block {self.path}"
                )

        reg.block = self
        self.regs[reg.name] = reg
        return reg

    def add_block(self, block):
        if block.name in self.blocks:
            raise ValueError(f"duplicate sub-block {block.name} in block {self.path}")

        block.parent = self
        self.blocks[block.name] = block
        return block

    def reg(self, name):
        return self.regs[name]

    def block(self, name):
        return self.blocks[name]

    def iter_regs(self):
        for reg in self.regs.values():
            yield reg
        for block in self.blocks.values():
            yield from block.iter_regs()

    def find_reg_by_addr(self, addr):
        for reg in self.iter_regs():
            if reg.addr == addr:
                return reg
        return None

    def find(self, path):
        item = self
        parts = path.split(".")
        if parts and parts[0] == self.name:
            parts = parts[1:]

        for part in parts:
            if isinstance(item, CsrBlock):
                if part in item.blocks:
                    item = item.blocks[part]
                elif part in item.regs:
                    item = item.regs[part]
                else:
                    raise KeyError(path)
            elif isinstance(item, CsrReg):
                item = item.fields[part]
            else:
                raise KeyError(path)

        return item

    def reset_values(self):
        return {reg.addr: reg.reset_value() for reg in self.iter_regs()}
