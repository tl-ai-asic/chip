# DMA IP Specification

## Overview

The DMA IP is a self-contained 32-bit memory-to-memory copy engine. Software programs source address, destination address, transfer length, and control registers through a simple ready/valid configuration interface. The DMA then issues one read request and one write request per 32-bit word.

The design intentionally uses simple custom interfaces so the IP can be simulated and synthesized without external bus packages.

## Features

- 32-bit data path.
- Parameterized address width.
- Register-controlled start, status, and interrupt enable.
- Multiple outstanding read and write transactions.
- Out-of-order read and write responses.
- Ready/valid memory request and response handshakes.
- Done and error status bits.
- Optional completion interrupt.

## Parameters

| Parameter | Default | Description |
| --- | ---: | --- |
| `ADDR_WIDTH` | 32 | Width of source and destination addresses. |
| `DATA_WIDTH` | 32 | Width of memory data. Must remain 32 for this baseline IP. |
| `MAX_OUTSTANDING_READS` | 4 | Maximum number of accepted read requests that may be waiting for read responses. |
| `MAX_OUTSTANDING_WRITES` | 4 | Maximum number of accepted write requests that may be waiting for write responses. |
| `MAX_TRANSFER_WORDS` | 4096 | Maximum legal value of `LEN_WORDS`. |
| `ID_WIDTH` | Derived | Width of request/response transaction IDs. Defaults to enough bits for all internal slots. |

## Register Map

All registers are 32-bit wide.

| Address | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `SRC_ADDR` | RW | Source byte address. |
| `0x04` | `DST_ADDR` | RW | Destination byte address. |
| `0x08` | `LEN_WORDS` | RW | Transfer length in 32-bit words. |
| `0x0C` | `CTRL` | RW | Bit 0: start. Bit 1: interrupt enable. |
| `0x10` | `STATUS` | RO/W1C | Bit 0: busy. Bit 1: done. Bit 2: error. |

Writing `1` to `STATUS.done` or `STATUS.error` clears the corresponding sticky status bit.

## Transfer Size

`LEN_WORDS` programs the DMA transfer length in 32-bit words.

| Limit | Value | Behavior |
| --- | ---: | --- |
| Minimum | 0 words | No read or write requests are initiated. The DMA completes the command and reports `STATUS.done`/`irq_done` normally. |
| Maximum | 4096 words by default | Largest legal value is set by `MAX_TRANSFER_WORDS`. The integrator must ensure the programmed source and destination address ranges are valid for the attached memory system. |

Although `LEN_WORDS` is exposed as a 32-bit software register, values larger than
`MAX_TRANSFER_WORDS` are illegal. Starting a descriptor with an over-limit length
sets `STATUS.error`, does not set `STATUS.busy`, and does not issue memory
traffic. Throughput for legal transfers is bounded by `MAX_OUTSTANDING_READS`,
`MAX_OUTSTANDING_WRITES`, and memory response latency.

For nonzero transfers, the source and destination byte ranges must not overlap.
The checked ranges are half-open intervals:
`[SRC_ADDR, SRC_ADDR + LEN_WORDS * 4)` and
`[DST_ADDR, DST_ADDR + LEN_WORDS * 4)`. Adjacent ranges are legal. Zero-length
transfers have no source or destination range and therefore cannot overlap.

## Configuration Interface

The configuration interface accepts one request at a time.

| Signal | Direction | Description |
| --- | --- | --- |
| `cfg_valid` | Input | Configuration request valid. |
| `cfg_write` | Input | `1` for write, `0` for read. |
| `cfg_addr[7:0]` | Input | Register byte address. |
| `cfg_wdata[31:0]` | Input | Register write data. |
| `cfg_ready` | Output | DMA can accept the request. |
| `cfg_rvalid` | Output | Read data is valid. |
| `cfg_rdata[31:0]` | Output | Register read data. |

The configuration interface always completes accepted accesses. Reads from
unimplemented register addresses return `cfg_rvalid` with `cfg_rdata == 0` and
set `STATUS.error`. Writes to unimplemented register addresses are ignored and
set `STATUS.error`.

## Memory Interface

The DMA uses separate read and write request channels.

| Signal | Direction | Description |
| --- | --- | --- |
| `rd_req_valid` | Output | Read request valid. |
| `rd_req_ready` | Input | Read request accepted. |
| `rd_req_id` | Output | Read transaction ID. Returned with the corresponding read response. |
| `rd_req_addr` | Output | Read byte address. |
| `rd_rsp_valid` | Input | Read response data valid. |
| `rd_rsp_ready` | Output | DMA can accept read response. |
| `rd_rsp_id` | Input | Read response transaction ID matching an accepted read request. |
| `rd_rsp_data` | Input | Read response data. |
| `wr_req_valid` | Output | Write request valid. |
| `wr_req_ready` | Input | Write request accepted. |
| `wr_req_id` | Output | Write transaction ID. Returned with the corresponding write response. |
| `wr_req_addr` | Output | Write byte address. |
| `wr_req_data` | Output | Write data. |
| `wr_rsp_valid` | Input | Write response valid. |
| `wr_rsp_ready` | Output | DMA can accept write response. |
| `wr_rsp_id` | Input | Write response transaction ID matching an accepted write request. |

Read and write responses may return out of order. The memory system must return the
same ID supplied on the corresponding request. The DMA asserts response ready only
for IDs that currently match an outstanding transaction of the expected type.

## Operation

1. Program `SRC_ADDR`, `DST_ADDR`, and `LEN_WORDS`.
2. Optionally set `CTRL.irq_en`.
3. Write `1` to `CTRL.start`.
4. DMA sets `STATUS.busy`.
5. DMA issues up to `MAX_OUTSTANDING_READS` read requests while free internal
   slots are available.
6. When a read response arrives, the DMA may issue that word's write request as
   soon as write credit is available. Writes do not wait for earlier chunks.
7. DMA accepts out-of-order write responses and counts the transfer complete
   after every write response has been received.
8. DMA clears `STATUS.busy` and sets `STATUS.done` when complete.
9. If `CTRL.irq_en` is set, `irq_done` asserts while `STATUS.done` is set.

Starting a zero-length transfer completes without issuing memory traffic and
sets `STATUS.done`.

Descriptor validation is performed when software writes `CTRL.start` to `1`.
Programming `SRC_ADDR`, `DST_ADDR`, or `LEN_WORDS` alone does not perform length
or overlap validation.

## Implementation Structure

The DMA top level contains register handling, transfer control, address
generation, and outstanding read/write counters. Transaction state is split into
two submodules:

- `dma_id_pool` allocates a free transaction ID when a read request is accepted
  and frees that ID when the corresponding write response completes.
- `dma_reorder_buffer` tracks each allocated slot from read outstanding, to write
  pending, to write outstanding. It stores the destination address and read data
  for each ID so any read response can become an independent write request.

## Error Handling

An error is reported when software attempts to start a transfer while the DMA is
already busy or when software starts a descriptor with `LEN_WORDS` greater than
`MAX_TRANSFER_WORDS`. A busy-start error does not interrupt the current transfer.
An over-limit descriptor does not start and issues no memory traffic.

An error is also reported when software starts a nonzero descriptor whose source
and destination ranges overlap. An overlapping descriptor does not start, does
not set `STATUS.busy`, and does not issue memory traffic.

While `STATUS.busy` is set, writes to `SRC_ADDR`, `DST_ADDR`, or `LEN_WORDS` are
rejected. The CSR access still completes, the programmed descriptor state is not
modified, and `STATUS.error` is set. Writes to `CTRL.irq_en` and W1C writes to
`STATUS.done`/`STATUS.error` remain accepted while busy.

Accesses to unimplemented CSR addresses are illegal. Invalid reads return zero
data and set `STATUS.error`; invalid writes are ignored and set `STATUS.error`.

`STATUS.error` is sticky until cleared. `irq_error` asserts while
`STATUS.error` and `CTRL.irq_en` are both set. If an error is reported while
`CTRL.irq_en` is clear, `STATUS.error` is still set but `irq_error` remains
deasserted.
