# riscv32imc_v3 Specification

## Overview

`riscv32imc_v3` is the carried-forward highest-throughput parallel version. It
builds on v1 by enabling parallel execution-engine issue/retirement paths,
scoreboarding, out-of-order write-back arbitration, parallel LSU issue with
memory hazard detection, and the timing-focused pipelined RV32M unit introduced
in v2. A sequential prefetch queue and simple-ALU fast path allow independent
non-control ALU streams to retire at one instruction per cycle.

The directory name follows the requested `riscv32imc_*` naming convention, but
this version implements the RV32IM instruction surface used by the current
RV32UI/RV32UM riscv-tests flow. Compressed `C` instructions are not implemented.

## Microarchitecture

- Scoreboarded issue tracks RAW, WAW, serial, outstanding, and engine
  availability hazards.
- A four-entry prefetch queue overlaps sequential instruction fetch with
  backend execution and write-back.
- Simple non-control ALU instructions (`LUI`, `AUIPC`, `OP-IMM`, and non-M
  `OP`) use a one-cycle fetch-queue-to-RVFI/write-back fast path when the
  scoreboard has no outstanding older instruction or busy destination register.
- ALU, multiply/divide, and LSU can have independent in-flight operations.
- RV32M uses a handshaked two-stage multiply/divide engine shared with v2.
  Multiplication consumes sixteen RHS bits per stage, division/remainder
  processes sixteen quotient bits per stage, and a small response FIFO
  arbitrates completed RV32M results onto the shared write-back path.
- Back-to-back independent M-extension instructions can stream directly from
  prefetch into the RV32M engine when the scoreboard reports no RAW/WAW or
  engine hazard, allowing the hazard-minimized M benchmark to reach one
  instruction per cycle.
- Write-back arbitration can retire whichever execution engine completes first,
  subject to the current arbitration priority.
- LSU accepts an independent younger load/store while an older LSU operation is
  pending when:
  - the two-entry LSU queue has space, and
  - byte-range memory hazard detection reports no overlapping access where
    either operation is a store.
- The external data-memory bus remains a single serialized request/response
  stream.
- RVFI trace is emitted for each retired instruction.

## Source Layout

- `logic/riscv32im_core.sv`: pipeline state registers, issue routing,
  simple-ALU fast path, write-back arbitration, and top-level wiring.
- `logic/riscv32im_scoreboard.sv`: dependency and execution-engine gating.
- `logic/riscv32im_scoreboard_types.sv`: packed inter-module structs.
- `logic/riscv32im_issue_prepare.sv`: ALU operation and operand selection.
- `logic/riscv32im_prefetch.sv`: four-entry instruction prefetch queue with
  redirect flush and outstanding response drain handling.
- `logic/riscv32im_alu_execute.sv`: branch, jump, system, CSR, and trap result
  generation.
- `logic/riscv32im_csr_file.sv`: CSR storage, writes, trap updates, and
  counters.
- `logic/riscv32im_rvfi_trace.sv`: retirement-to-RVFI trace generation.
- `logic/riscv32im_lsu.sv`: two-entry LSU with parallel issue and byte-range
  memory hazard detection.
- `logic/riscv32im_lsu_format.sv`: LSU access formatting.
- `logic/riscv32im_alu.sv`, `logic/riscv32im_muldiv.sv`,
  `logic/riscv32im_decode.sv`, and `logic/riscv32im_csr_read.sv`: reusable
  leaf blocks.

## Verification

Run smoke and riscv-tests:

```sh
make -C ip/riscv/riscv32imc_v3/tb
make -C ip/riscv/riscv32imc_v3/tb run-riscv-tests
make -C ip/riscv/riscv32imc_v3/tb run-ipc-tests
```

The shared cocotb LSU test requires the LSU pending count to reach at least two,
which proves independent memory operations are accepted while an older LSU
operation is pending.

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
responses after the configured latency.
