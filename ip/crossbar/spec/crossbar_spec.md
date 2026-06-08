# AXI/APB Crossbar IP Specification

## Overview

The AXI/APB crossbar routes transactions from two upstream AMBA ports to two
downstream AMBA ports:

- One full AXI4 slave upstream port.
- One AXI4-Lite slave upstream port.
- One full AXI4 master downstream port.
- One APB4 master downstream port.

The selected downstream port is chosen from the transaction address. Decode
misses complete on the originating upstream port with AMBA error responses and
do not issue downstream traffic.

## Features

- Parameterized address, data, and AXI ID widths.
- Independent read and write datapaths.
- AXI4 to AXI4 forwarding for full bursts.
- AXI4-Lite to AXI4 conversion as single-beat AXI4 transactions.
- AXI4 and AXI4-Lite to APB4 conversion.
- Address-map based routing to separate AXI and APB address spaces.
- Decode errors returned as `DECERR`.
- APB `PSLVERR` returned as `SLVERR`.

## Parameters

| Parameter | Default | Description |
| --- | ---: | --- |
| `ADDR_WIDTH` | 32 | Address width for every AMBA interface. |
| `DATA_WIDTH` | 32 | Data width for AXI, AXI4-Lite, and APB. Must be byte-addressable. |
| `ID_WIDTH` | 4 | AXI ID width for full AXI upstream/downstream ports. |
| `AXI_BASE_ADDR` | `0x0000_0000` | Base address for the downstream AXI4 address region. |
| `AXI_ADDR_MASK` | `0xF000_0000` | Address mask for matching the downstream AXI4 region. |
| `APB_BASE_ADDR` | `0x1000_0000` | Base address for the downstream APB4 address region. |
| `APB_ADDR_MASK` | `0xF000_0000` | Address mask for matching the downstream APB4 region. |

An address matches a region when `(addr & mask) == (base & mask)`.

## Address Map

The AXI and APB downstream ports each own a separate address region. A
transaction is routed using the first address of its AXI address phase.

| Match | Route | Response behavior |
| --- | --- | --- |
| `AXI_BASE_ADDR`/`AXI_ADDR_MASK` | Downstream AXI4 master port | Response is forwarded from downstream AXI4. |
| `APB_BASE_ADDR`/`APB_ADDR_MASK` | Downstream APB4 master port | APB success maps to `OKAY`; `PSLVERR` maps to `SLVERR`. |
| No match | No downstream access | Originating upstream receives `DECERR`. |

AXI bursts must remain inside the address region selected by the first address.
The block intentionally does not split a burst across downstream ports.

## AXI4 Upstream Behavior

The full AXI4 upstream port is implemented as an AXI4 slave interface with
standard AW, W, B, AR, and R channels.

The crossbar accepts one write transaction and one read transaction at a time
from the full AXI4 upstream port. It uses AXI backpressure to enforce this
limit. Read and write channels are independent, so one read and one write may be
active concurrently.

Writes to the downstream AXI4 port forward AW, W, and B channel attributes,
including ID, burst length, size, burst type, lock, cache, protection, and QoS.
Reads to the downstream AXI4 port forward AR attributes and return downstream R
beats directly to the AXI4 upstream port.

Writes to the APB4 port consume one AXI W beat per APB write transfer. The
write response is returned after every beat in the AXI write burst has completed.
Reads to the APB4 port issue one APB read transfer per AXI R beat.

## AXI4-Lite Upstream Behavior

The AXI4-Lite upstream port is implemented as an AXI4-Lite slave interface.
Address and data phases may arrive independently. The crossbar buffers one
AXI4-Lite write address, one write data beat, and one read address.

AXI4-Lite transactions routed to the downstream AXI4 port are converted to
single-beat AXI4 transactions with `AxLEN == 0`, `AxBURST == INCR`, and
`AxSIZE` set from `DATA_WIDTH`.

## APB4 Downstream Behavior

The APB downstream port is an APB4 master interface. It drives `PADDR`,
`PPROT`, `PSEL`, `PENABLE`, `PWRITE`, `PWDATA`, and `PSTRB`, and samples
`PRDATA`, `PREADY`, and `PSLVERR`.

APB accesses are serialized because APB has a single non-pipelined transfer
interface. When read and write APB transfers are both pending, writes have
priority for the next APB transfer.

## Error Handling

Decode misses return `DECERR`:

- AXI4 writes consume all W beats for the accepted AW transaction, then return a
  single B response with `BRESP == DECERR`.
- AXI4 reads return the requested number of R beats with `RRESP == DECERR` and
  zero data. The final beat asserts `RLAST`.
- AXI4-Lite reads and writes return one `DECERR` response.

APB slave errors return `SLVERR`. For APB-routed AXI4 write bursts, any APB beat
with `PSLVERR` causes the final AXI B response to be `SLVERR`.

## Limitations

- The full AXI4 upstream port supports one outstanding read transaction and one
  outstanding write transaction at a time.
- The crossbar routes an entire AXI burst using the first address. It does not
  split bursts or re-decode each beat for downstream selection.
- APB conversion increments addresses for all non-`FIXED` bursts. Integrators
  should use `FIXED` or `INCR` bursts for APB-routed traffic.
