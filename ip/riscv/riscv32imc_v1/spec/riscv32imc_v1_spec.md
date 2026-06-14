# riscv32imc_v1 Specification

## Overview

`riscv32imc_v1` is a serialized in-order microarchitecture partitioned into
submodules. It removes scoreboard-based hazard tracking and waits for the
currently issued instruction to retire before issuing the next instruction. A
four-entry sequential prefetch queue can fetch ahead while non-control
instructions move through decode, execution, and write-back. Simple non-control
ALU instructions can retire directly from the prefetch queue at one instruction
per cycle; other instructions still use the conservative serialized path.

The directory name follows the requested `riscv32imc_*` naming convention, but
this version implements the RV32IM instruction surface used by the current
RV32UI/RV32UM riscv-tests flow. Compressed `C` instructions are not implemented.

## Microarchitecture

- In-order fetch, issue, execution, and retirement.
- No scoreboard and no explicit RAW/WAW hazard tracking.
- Issue is allowed only when the ALU, multiply/divide, and LSU paths are idle.
- After an instruction issues, the core waits in write-back until that
  instruction retires before returning to fetch.
- Simple non-control ALU instructions (`LUI`, `AUIPC`, `OP-IMM`, and non-M
  `OP`) use a one-cycle fetch-queue-to-RVFI/write-back fast path. This keeps
  architectural retirement in order while allowing 1 IPC on independent ALU
  streams.
- A four-entry prefetch queue overlaps sequential instruction fetch with
  non-control decode, execution, and write-back cycles. Control-flow and trap
  retirements redirect the prefetch PC, discard buffered fall-through
  instructions, and drain outstanding wrong-path fetch responses before issuing
  new requests.
- Submodule partitioning for decode, ALU operand preparation, ALU/control
  execution, CSR file, RVFI trace generation, LSU, and multiply/divide.
- LSU memory issue remains serialized with one accepted LSU operation at a time.

## Source Layout

- `logic/riscv32im_core.sv`: pipeline state registers, issue routing,
  simple-ALU fast path, write-back arbitration, and top-level wiring.
- `logic/riscv32im_types.sv`: packed inter-module structs for LSU, ALU execute,
  and RVFI trace interfaces.
- `logic/riscv32im_issue_prepare.sv`: ALU operation and operand selection.
- `logic/riscv32im_prefetch.sv`: four-entry instruction prefetch queue with
  redirect flush and outstanding response drain handling.
- `logic/riscv32im_alu_execute.sv`: branch, jump, system, CSR, and trap result
  generation.
- `logic/riscv32im_csr_file.sv`: CSR storage, writes, trap updates, and
  counters.
- `logic/riscv32im_rvfi_trace.sv`: retirement-to-RVFI trace generation.
- `logic/riscv32im_lsu.sv`: serialized LSU matching the base core's
  one-operation memory issue behavior.
- `logic/riscv32im_lsu_format.sv`: LSU access formatting.
- `logic/riscv32im_alu.sv`, `logic/riscv32im_muldiv.sv`,
  `logic/riscv32im_decode.sv`, and `logic/riscv32im_csr_read.sv`: reusable
  leaf blocks.

## Verification

Run smoke and riscv-tests:

```sh
make -C ip/riscv/riscv32imc_v1/tb
make -C ip/riscv/riscv32imc_v1/tb run-riscv-tests
make -C ip/riscv/riscv32imc_v1/tb run-ipc-tests
```

The shared cocotb LSU test checks that the independent-load program completes,
but does not require multiple pending LSU operations for this version because
the LSU behavior is intentionally aligned with base.

The IPC perf tests compile and run the shared assembly benchmarks in
`ip/riscv/benchmarks`. Each benchmark exports `workload_start` and
`workload_end` symbols around an identical 500-instruction hazard-minimized
window used by every core version. The benchmark set covers basic RV32I ALU,
multiply/divide, load/store, mixed ALU/LSU/multiply instruction streams, and a
branch-loop workload with multiple loops including one nested loop. Loop
benchmarks can export `workload_expected_retired` when the measured dynamic
retire count differs from the static instruction window size.

IPC benchmark runs use a 2-cycle pipelined instruction-memory and data-memory
response model. Back-to-back accepted requests can produce back-to-back
responses after the fixed latency.
