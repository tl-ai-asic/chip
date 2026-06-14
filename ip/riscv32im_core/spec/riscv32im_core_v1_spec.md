# riscv32im_core v1 Specification

## Overview

`logic_v1` is the baseline RV32IM implementation. It uses the original
single-issue, non-scoreboarded control approach: the top-level core owns the
main prefetch/decode/execute/write-back state machine, CSR state, RVFI
retirement bookkeeping, and trap/PC sequencing.

This version intentionally does not support parallel execution. Only one
instruction is allowed to make architectural progress through the execution and
write-back path at a time.

## Source Layout

- `logic_v1/riscv32im_core.sv`: top-level controller, register file, CSR state,
  RVFI retirement, issue sequencing, traps, and write-back.
- `logic_v1/riscv32im_alu.sv`: RV32I ALU and compare operations.
- `logic_v1/riscv32im_muldiv.sv`: RV32M multiply/divide/remainder operations.
- `logic_v1/riscv32im_decode.sv`: instruction field extraction and legality
  classification.
- `logic_v1/riscv32im_csr_read.sv`: combinational CSR read mux.
- `logic_v1/riscv32im_lsu.sv`: single-operation LSU.
- `logic_v1/riscv32im_lsu_format.sv`: LSU byte-lane, split-access, and load
  formatting helpers.

## Execution Model

- No scoreboard.
- No parallel execution between ALU, multiply/divide, and LSU engines.
- LSU accepts one memory operation at a time.
- Serializing instructions are handled by the main state machine.
- RVFI emits one retired instruction per architectural write-back.

## Verification Expectations

The shared cocotb testbench can run this version with:

```sh
make -C ip/riscv32im_core/tb CORE_VERSION=v1
```

The LSU parallelism test still runs the independent-load program, but it does
not require multiple pending LSU operations for v1.

