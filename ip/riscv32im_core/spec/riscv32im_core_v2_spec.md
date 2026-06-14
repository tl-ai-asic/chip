# riscv32im_core v2 Specification

## Overview

`logic_v2` is the modular scoreboarded implementation without LSU parallel
issue. It keeps the separated pipeline/helper modules from v3, including the
scoreboard and independent execution-engine write-back paths, but the LSU only
accepts a new memory operation when no older LSU operation is pending.

This version is useful for comparing the scoreboarded multi-engine issue path
against a conservative, serialized memory subsystem.

## Source Layout

- `logic_v2/riscv32im_core.sv`: pipeline state registers, issue routing,
  write-back arbitration, and top-level wiring.
- `logic_v2/riscv32im_scoreboard.sv`: RAW/WAW, serial, outstanding, and engine
  availability tracking.
- `logic_v2/riscv32im_scoreboard_types.sv`: packed structs for compact
  inter-module interfaces.
- `logic_v2/riscv32im_issue_prepare.sv`: ALU operand and operation selection.
- `logic_v2/riscv32im_alu_execute.sv`: branch/jump/system/CSR/trap result
  generation.
- `logic_v2/riscv32im_csr_file.sv`: CSR state, trap updates, and counters.
- `logic_v2/riscv32im_rvfi_trace.sv`: RVFI output register generation.
- `logic_v2/riscv32im_lsu.sv`: queued LSU implementation configured to expose
  ready only when no LSU operation is pending.
- `logic_v2/riscv32im_lsu_format.sv`: LSU access formatting.
- `logic_v2/riscv32im_alu.sv`, `logic_v2/riscv32im_muldiv.sv`,
  `logic_v2/riscv32im_decode.sv`, and `logic_v2/riscv32im_csr_read.sv`:
  reusable leaf blocks.

## Execution Model

- Scoreboarded issue checks RAW, WAW, serial, and execution-engine availability.
- ALU, multiply/divide, and LSU can have independent write-back interfaces.
- The LSU memory queue is not used for parallel issue in this version:
  `issue_ready_o` is asserted only when the pending LSU count is zero.
- RVFI emits one retired instruction from the write-back arbitration point.

## Verification Expectations

Run with:

```sh
make -C ip/riscv32im_core/tb CORE_VERSION=v2
```

The shared LSU independent-load test expects the program to pass, but it does
not require two simultaneously pending LSU operations for v2.

