# riscv32imc_base Specification

## Overview

`riscv32imc_base` is the baseline RV32IM machine-mode core. It keeps the
original flat top-level implementation style: the top module owns prefetch,
decode, execution, retirement, CSR state, trap handling, and RVFI trace
bookkeeping. It is intended as the simplest reference implementation.

The directory name follows the requested `riscv32imc_*` naming convention, but
this version implements the RV32IM instruction surface used by the current
RV32UI/RV32UM riscv-tests flow. Compressed `C` instructions are not implemented.

## Microarchitecture

- In-order issue.
- In-order execution.
- In-order retirement.
- No scoreboard.
- No RAW/WAW/control hazard tracking.
- The core fetches the next instruction only after the current instruction has
  retired.
- No parallel execution across ALU, multiply/divide, and LSU.
- LSU accepts one memory operation at a time.
- RVFI trace fields are exposed at the top level.

## Source Layout

- `logic/riscv32im_core.sv`: flat top-level controller, GPRs, CSRs, RVFI, trap
  and PC sequencing, and write-back.
- `logic/riscv32im_alu.sv`: RV32I ALU and compare operations.
- `logic/riscv32im_muldiv.sv`: RV32M multiply/divide/remainder operations.
- `logic/riscv32im_decode.sv`: instruction field extraction and legality
  classification.
- `logic/riscv32im_csr_read.sv`: combinational CSR read mux.
- `logic/riscv32im_lsu.sv`: single-operation load/store unit.
- `logic/riscv32im_lsu_format.sv`: LSU byte lane and split-access formatting.

## Verification

Run smoke and riscv-tests:

```sh
make -C ip/riscv/riscv32imc_base/tb
make -C ip/riscv/riscv32imc_base/tb run-riscv-tests
make -C ip/riscv/riscv32imc_base/tb run-ipc-tests
```

The shared cocotb LSU test checks functional completion for this core but does
not require multiple pending LSU operations.

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
