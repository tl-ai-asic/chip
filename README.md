# Chip Design Project

This repository contains self-contained SystemVerilog IP blocks.

## Directory Layout

```text
ip/
  dma/
    spec/   Design specifications in Markdown
    logic/  Synthesizable SystemVerilog source
    tb/     Testbench source
    synth/  Synthesis scripts
```

## Current IP

- `ip/dma`: Register-controlled 32-bit memory-to-memory DMA engine.
- `ip/crossbar`: AXI4/AXI4-Lite upstream to AXI4/APB address-decoding crossbar.
- `ip/lru_cache`: Set-associative word cache with exact LRU replacement.
- `ip/riscv`: Maintained RISC-V core family with base and v1-v4 RV32IM variants,
  machine-mode CSR/trap support, and RVFI trace interfaces.

## Reusable OpenROAD Flow

Run synthesis, basic OpenROAD placement/global-route, and timing/area/power
reports for a block:

```sh
./flow/run_block_flow.sh ip/dma/flow.env
```

Each IP can provide a `flow.env` with the top module, RTL files, clock, reset
treatment, and floorplan overrides. Generated outputs are written under
`build/openroad/<block>/`.
