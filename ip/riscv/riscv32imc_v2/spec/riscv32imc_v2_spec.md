# riscv32imc_v2 Specification

## Overview

`riscv32imc_v2` is based on `riscv32imc_v1`. It keeps the same in-order
issue, execution, write-back, and retirement model, but moves RV32M behind a
dedicated handshaked execution module so the core boundary is ready for timing
experiments without adding v3-style parallel issue.

There is no general scoreboard, no ALU/LSU/RV32M multi-engine parallel issue,
no out-of-order write-back across execution engines, and no parallel LSU issue
in v2. Those features belong to `riscv32imc_v3`. v2 does include a narrow
RV32M stream path for back-to-back independent M-extension instructions.

The directory name follows the requested `riscv32imc_*` naming convention, but
this version implements the RV32IM instruction surface used by the current
RV32UI/RV32UM riscv-tests flow. Compressed `C` instructions are not implemented.

## Microarchitecture

- Four visible stages: prefetch, decode, execution, and write-back.
- A four-entry prefetch queue overlaps sequential instruction fetch with the
  backend and flushes on redirects.
- Simple non-control ALU instructions (`LUI`, `AUIPC`, `OP-IMM`, and non-M
  `OP`) use the same fast path as v1, allowing a hazard-minimized ALU stream to
  retire at one instruction per cycle.
- Non-fast-path instructions issue in order and the core waits for write-back
  before issuing the next instruction.
- RV32M uses a handshaked two-stage engine. Multiplication consumes sixteen RHS
  bits per stage, while division/remainder processes sixteen quotient bits per
  stage. The engine can accept one independent M instruction per cycle.
- Back-to-back M instructions can stream directly from prefetch into the RV32M
  engine when a small pending-destination check proves no RAW/WAW dependency
  against older in-flight M instructions.
- When the next instruction is not an independent M instruction, v2 waits for
  all older in-flight M instructions to retire before resuming the normal
  in-order decode/execution/write-back path.
- LSU accepts one memory operation at a time and waits for the data-memory
  response before the instruction retires.
- RVFI trace is emitted for each retired instruction.

## Source Layout

- `logic/riscv32im_core.sv`: in-order pipeline state registers, fast ALU path,
  serialized issue/write-back, and top-level wiring.
- `logic/riscv32im_types.sv`: packed inter-module structs shared by LSU,
  RV32M, and RVFI helpers.
- `logic/riscv32im_issue_prepare.sv`: ALU operation and operand selection.
- `logic/riscv32im_prefetch.sv`: four-entry instruction prefetch queue with
  redirect flush and outstanding response drain handling.
- `logic/riscv32im_alu_execute.sv`: branch, jump, system, CSR, and trap result
  generation.
- `logic/riscv32im_csr_file.sv`: CSR storage, writes, trap updates, and
  counters.
- `logic/riscv32im_rvfi_trace.sv`: retirement-to-RVFI trace generation.
- `logic/riscv32im_lsu.sv`: serialized LSU.
- `logic/riscv32im_lsu_format.sv`: LSU access formatting.
- `logic/riscv32im_alu.sv`, `logic/riscv32im_muldiv.sv`,
  `logic/riscv32im_decode.sv`, and `logic/riscv32im_csr_read.sv`: reusable
  leaf blocks.

## Verification

Run smoke, riscv-tests, and IPC benchmarks:

```sh
make -C ip/riscv/riscv32imc_v2/tb
make -C ip/riscv/riscv32imc_v2/tb run-riscv-tests
make -C ip/riscv/riscv32imc_v2/tb run-ipc-tests
```

The shared cocotb LSU test expects v2 to keep only one pending LSU operation.

The IPC perf tests compile and run the shared assembly benchmarks in
`ip/riscv/benchmarks`. Each benchmark exports `workload_start` and
`workload_end` symbols around an identical hazard-minimized window used by every
core version. The benchmark set covers basic RV32I ALU, multiply/divide,
load/store, mixed ALU/LSU/multiply instruction streams, and a branch-loop
workload with multiple loops including one nested loop.

IPC benchmark runs use a 2-cycle pipelined instruction-memory and data-memory
response model. Back-to-back accepted requests can produce back-to-back
responses after the configured latency.
