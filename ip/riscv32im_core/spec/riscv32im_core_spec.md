# riscv32im_core Specification

## Overview

`riscv32im_core` is a simple in-order RV32IM machine-mode core intended for
IP-level simulation and trace collection. It retires at most one instruction at
a time, uses separate instruction and data request/response ports, and exposes
an RVFI-compatible trace interface for every retired instruction.

The IP contains three selectable RTL versions. See
`riscv32im_core_v1_spec.md`, `riscv32im_core_v2_spec.md`, and
`riscv32im_core_v3_spec.md` for version-specific architecture details.

The implementation targets the integer `I` and multiply/divide `M` extensions.
It also includes the small machine-mode CSR and trap subset needed by standard
bare-metal `riscv-tests` environments.

The top-level controller is organized as four front-end stages: prefetch,
decode, execution/issue, and write-back arbitration. The front end issues one
instruction per cycle when the target execution engine is available and the
scoreboard reports no RAW or WAW dependency on earlier issued instructions.
Independent ALU, multiply/divide, and LSU operations may be in flight at the
same time.

The scoreboard tracks pending GPR destinations for all issued instructions.
Branches, jumps, fences, CSR instructions, and traps are treated as serializing
operations: they wait for older issued work to complete and block younger
fetches until their PC/CSR/trap effects write back.

The datapath is split into reusable leaf blocks:

- `riscv32im_scoreboard_types.sv`: shared packed scoreboard and LSU
  issue/response structs used to keep inter-module wiring compact.
- `riscv32im_scoreboard`: pending destination tracking, RAW/WAW hazard checks,
  serializing-operation tracking, and execution-engine availability gating.
- `riscv32im_alu`: normal RV32I ALU and compare operations.
- `riscv32im_muldiv`: RV32M multiply, divide, and remainder operations.
- `riscv32im_decode`: instruction field extraction, legality checks,
  operand-use classification, serializing-operation detection, and execution
  engine selection for the issue scoreboard.
- `riscv32im_csr_read`: combinational CSR read mux.
- `riscv32im_csr_file`: machine CSR storage, CSR writes, trap CSR updates, and
  `mcycle`/`minstret` counters.
- `riscv32im_issue_prepare`: issue-stage ALU operation and operand selection
  for integer, branch-compare, and load/store address generation.
- `riscv32im_alu_execute`: ALU/control execution result generation for
  branches, jumps, fences, CSR operations, traps, and write-back metadata.
- `riscv32im_lsu`: queued data-memory request sequencing, byte-range hazard
  checks, unaligned split accesses, load formatting, and RVFI memory trace
  data. The LSU owns data-memory side effects while its write-back interface
  returns load/trap and trace metadata.
- `riscv32im_lsu_format`: LSU byte-lane masks, split-access detection, store
  data alignment, and load data formatting.
- `riscv32im_rvfi_trace`: retirement-to-RVFI trace register generation and
  order counter management.

## Top-Level Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `RESET_VECTOR` | `32'h8000_0000` | First fetch address after reset. |
| `HART_ID` | `32'h0000_0000` | Value returned by `mhartid`. |

## Clock and Reset

| Signal | Direction | Description |
| --- | --- | --- |
| `clk` | Input | Core clock. |
| `rst_n` | Input | Active-low asynchronous reset. |

On reset the program counter is loaded from `RESET_VECTOR`, integer registers
are cleared, and machine CSRs are initialized to a minimal machine-mode state.

## Instruction Memory Interface

The instruction port is a single-outstanding request/response interface.

| Signal | Direction | Description |
| --- | --- | --- |
| `imem_req_valid` | Output | Fetch request valid. |
| `imem_req_ready` | Input | Fetch request accepted. |
| `imem_req_addr[31:0]` | Output | Byte address of the instruction fetch. |
| `imem_rsp_valid` | Input | Fetch response valid. |
| `imem_rsp_rdata[31:0]` | Input | Fetched instruction word. |
| `imem_rsp_err` | Input | Instruction access fault response. |

## Data Memory Interface

The data port is a single-outstanding request/response interface. Addresses are
byte addresses. Write data and strobes are lane-aligned to `addr[1:0]`.

| Signal | Direction | Description |
| --- | --- | --- |
| `dmem_req_valid` | Output | Data request valid. |
| `dmem_req_ready` | Input | Data request accepted. |
| `dmem_req_write` | Output | `1` for store, `0` for load. |
| `dmem_req_addr[31:0]` | Output | Byte address. |
| `dmem_req_wdata[31:0]` | Output | Store data shifted onto byte lanes. |
| `dmem_req_wstrb[3:0]` | Output | Store byte enables. |
| `dmem_rsp_valid` | Input | Data response valid. |
| `dmem_rsp_rdata[31:0]` | Input | Load response data. |
| `dmem_rsp_err` | Input | Load/store access fault response. |

The LSU can hold two pending memory operations. A younger load/store may issue
while an older LSU operation is pending when the queue has space and its byte
range does not overlap an older pending memory operation where either operation
is a store. The external data-memory port still emits one request stream, so
accepted LSU operations are serialized onto the bus while the front end can keep
issuing independent memory work.

Misaligned halfword and word loads/stores are supported by issuing two aligned
data-memory beats when an access crosses a 32-bit word boundary.

## RVFI Trace Interface

The core exposes the common RVFI fields:

`rvfi_valid`, `rvfi_order`, `rvfi_insn`, `rvfi_trap`, `rvfi_halt`, `rvfi_intr`,
`rvfi_mode`, `rvfi_ixl`, source/destination register fields, PC fields, and
memory address/mask/data fields.

`rvfi_valid` pulses once for each retired instruction. Trap-causing
instructions also retire and assert `rvfi_trap`. `rvfi_mode` is fixed to
machine mode (`2'b11`) and `rvfi_ixl` is fixed to RV32 (`2'b01`).

## Supported ISA Surface

Supported instruction groups:

- RV32I arithmetic, logic, shifts, branches, jumps, loads, stores, `LUI`,
  `AUIPC`
- RV32M `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`
- `FENCE` and `FENCE.I` as ordering no-ops
- Machine-mode CSR read/write/set/clear instructions
- `ECALL`, `EBREAK`, `MRET`, and `WFI`

Implemented CSRs include `mstatus`, `mtvec`, `mscratch`, `mepc`, `mcause`,
`mtval`, `mhartid`, `mcycle`, `minstret`, and the read-only `cycle`, `time`,
and `instret` aliases.

## Cocotb Usage

Run the built-in smoke program:

```sh
cd ip/riscv32im_core/tb
make
```

Run one or more externally built riscv-tests ELF or raw binary images:

```sh
cd ip/riscv32im_core/tb
make RISCV_BINARY=/path/to/rv32ui-p-add
make RISCV_BINARIES="/path/to/rv32ui-p-add /path/to/rv32um-p-mul"
```

Build and run the RV32UI/RV32UM p-mode riscv-tests from an installed
`riscv-tests` checkout:

```sh
cd ip/riscv32im_core/tb
make run-riscv-tests RISCV_TESTS_ROOT=$HOME/tools/riscv/src/riscv-tests
```

For ELF files, the testbench loads `PT_LOAD` segments and uses the `tohost`
symbol when present. For raw binaries, the image is loaded at
`RISCV_BINARY_BASE` or `RESET_VECTOR`; set `RISCV_TOHOST` when the pass/fail
mailbox is not at `RESET_VECTOR + 0x1000`.
