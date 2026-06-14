# RISC-V Core Variant Summary

Summary date: June 14, 2026

This directory contains four RV32IM core implementations used for architecture
and implementation tradeoff experiments. The directory names use the requested
`riscv32imc_*` convention, but the current RTL implements the RV32IM
instruction surface exercised by RV32UI/RV32UM riscv-tests. Compressed `C`
instructions are not implemented.

## Variants

| Version | Intent | Issue / retirement model | Prefetch | RV32M | LSU | Hazard handling |
|---|---|---|---|---|---|---|
| `riscv32imc_base` | Flat baseline reference | Fully serialized in-order issue, execution, and retirement | No fetch ahead beyond current instruction | Combinational M result in the flat execution path | One memory op at a time | No scoreboard or explicit RAW/WAW tracking |
| `riscv32imc_v1` | Modularized in-order core | In-order issue/execution/retirement with a simple ALU fast path | 4-entry sequential prefetch queue | Combinational M path; non-fast-path M ops serialize | One memory op at a time | No scoreboard; issue waits for previous non-fast-path op to retire |
| `riscv32imc_v2` | v1 plus higher-throughput RV32M | Same in-order model as v1, plus direct streaming for independent M ops | 4-entry sequential prefetch queue | One-cycle registered handshaked M unit; accepts one independent M op per cycle | One memory op at a time | Narrow pending-destination check for back-to-back M stream; no general scoreboard |
| `riscv32imc_v3` | Parallel execution experiment | Scoreboarded issue with independent ALU, RV32M, and LSU completion paths | 4-entry sequential prefetch queue | Handshaked M unit with one independent M op per cycle | Two-entry LSU accepts independent non-conflicting memory ops | Scoreboard checks RAW/WAW, serial ops, engine availability, and memory hazards |

## Measurement Setup

- IPC command: `make -C ip/riscv/<version>/tb run-ipc-tests`
- IPC memory model: 2-cycle pipelined instruction and data memory latency.
  Back-to-back accepted requests can return back-to-back responses after the
  fixed latency.
- Physical command: `./flow/run_block_flow.sh ip/riscv/<version>/flow.env`
- Physical reports: OpenROAD post-global-route reports in
  `build/openroad/<version>/reports/`
- Technology and clock target: Nangate45, 10 ns target clock.
- Power is OpenROAD vectorless/default activity power from `post_grt_power.rpt`;
  use it for relative comparison only.
- Estimated period is `10 ns - setup WNS`. Estimated Fmax is `1000 / estimated
  period`.

## IPC Comparison

All IPC suites passed with `TESTS=6 PASS=6 FAIL=0` for each version.

| Version | ALU IPC | MUL/DIV IPC | LSU IPC | Mixed IPC | Branch IPC | Random IPC |
|---|---:|---:|---:|---:|---:|---:|
| `riscv32imc_base` | 0.1431 | 0.1431 | 0.0771 | 0.1001 | 0.1430 | 0.1190 |
| `riscv32imc_v1` | 1.0000 | 0.3338 | 0.1113 | 0.1667 | 0.3451 | 0.2214 |
| `riscv32imc_v2` | 1.0000 | 1.0000 | 0.1113 | 0.1667 | 0.3451 | 0.2239 |
| `riscv32imc_v3` | 1.0000 | 1.0000 | 0.1669 | 0.3322 | 0.3451 | 0.3425 |

## Area, Timing, And Power

| Version | Area (um^2) | Setup WNS (ns) | Hold WNS (ns) | Est. period (ns) | Est. Fmax (MHz) | Total power (mW) |
|---|---:|---:|---:|---:|---:|---:|
| `riscv32imc_base` | 53,208 | -29.478 | 0.023 | 39.478 | 25.3 | 811.00 |
| `riscv32imc_v1` | 68,570 | -29.908 | 0.038 | 39.908 | 25.1 | 6.00 |
| `riscv32imc_v2` | 71,107 | -59.725 | 0.040 | 69.725 | 14.3 | 710.00 |
| `riscv32imc_v3` | 49,852 | -61.881 | 0.053 | 71.881 | 13.9 | 7.59 |

## Observations

- `v1` is the first version to reach 1.0 IPC on the ALU benchmark because the
  prefetch queue and simple-ALU fast path remove the base core's serialized
  fetch/decode/execute/write-back loop.
- `v2` keeps the v1 in-order architecture but improves MUL/DIV throughput to
  1.0 IPC for independent back-to-back M instructions.
- `v3` improves memory-heavy and mixed workloads by allowing independent LSU
  and execution-engine work to overlap under scoreboard control.
- The branch-loop benchmark is identical for v1, v2, and v3 because the current
  versions share the same sequential prefetch behavior and no branch predictor.
- The post-route timing target is not met by any version at 10 ns. The reported
  WNS values are useful for relative comparison, but future timing experiments
  should focus on the longest combinational paths before treating the estimated
  Fmax values as final.
- The vectorless power estimate is very sensitive to large combinational cones.
  Base and v2 report much higher dynamic power than v1 and v3; use gate-level
  switching activity from representative workloads before making final power
  decisions.

## Reproducing This Snapshot

```sh
for core in riscv32imc_base riscv32imc_v1 riscv32imc_v2 riscv32imc_v3; do
  make -C "ip/riscv/$core/tb" run-ipc-tests
  ./flow/run_block_flow.sh "ip/riscv/$core/flow.env"
done
```
