# riscv32im_core v3 Specification

## Overview

`logic_v3` is the current modular implementation. It keeps the scoreboarded
multi-engine issue path and enables the LSU to accept independent memory
operations while older LSU operations are still pending, subject to byte-range
memory hazard checks.

This is the highest-throughput version in this set.

## Source Layout

- `logic_v3/riscv32im_core.sv`: pipeline state registers, issue routing,
  write-back arbitration, and top-level wiring.
- `logic_v3/riscv32im_scoreboard.sv`: RAW/WAW, serial, outstanding, and engine
  availability tracking.
- `logic_v3/riscv32im_scoreboard_types.sv`: packed structs for compact
  inter-module interfaces.
- `logic_v3/riscv32im_issue_prepare.sv`: ALU operand and operation selection.
- `logic_v3/riscv32im_alu_execute.sv`: branch/jump/system/CSR/trap result
  generation.
- `logic_v3/riscv32im_csr_file.sv`: CSR state, trap updates, and counters.
- `logic_v3/riscv32im_rvfi_trace.sv`: RVFI output register generation.
- `logic_v3/riscv32im_lsu.sv`: two-entry LSU with memory byte-range hazard
  checks and parallel issue for independent memory operations.
- `logic_v3/riscv32im_lsu_format.sv`: LSU access formatting.
- `logic_v3/riscv32im_alu.sv`, `logic_v3/riscv32im_muldiv.sv`,
  `logic_v3/riscv32im_decode.sv`, and `logic_v3/riscv32im_csr_read.sv`:
  reusable leaf blocks.

## Execution Model

- Scoreboarded issue checks RAW, WAW, serial, and execution-engine availability.
- ALU, multiply/divide, and LSU can have independent write-back interfaces.
- LSU accepts a younger load/store while an older LSU operation is pending if
  the queue has space and no byte-overlap hazard exists where either operation
  is a store.
- The external data-memory bus remains a single serialized request stream.
- RVFI emits one retired instruction from the write-back arbitration point.

## Verification Expectations

Run with:

```sh
make -C ip/riscv32im_core/tb CORE_VERSION=v3
```

The shared LSU independent-load test requires the v3 LSU pending count to reach
at least two, proving that independent memory operations can be accepted while
an older LSU operation is pending.

