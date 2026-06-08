# Multi-Thread DMA IP Specification

## Overview

The multi-thread DMA IP is a parameterized memory-to-memory copy engine with
`THREAD_COUNT` independently programmable DMA threads. Software can start
multiple threads in parallel. All active threads share one read request channel,
one write request channel, and one global transaction ID pool.

The design keeps the baseline DMA ready/valid interfaces, outstanding read/write
behavior, out-of-order response handling, descriptor validation, done/error
status, and optional interrupts.

## Features

- Parameterized thread count, address width, and outstanding transaction limits.
- Independent source, destination, length, control, status, and progress
  registers per thread.
- Multiple threads may be busy at the same time.
- Shared memory request interface and shared transaction ID pool.
- Round-robin read issue arbitration across active threads.
- ID-indexed reorder buffer that stores the owning thread for every in-flight
  transaction.
- Out-of-order read and write response support.
- Per-thread done and error interrupts.

## Parameters

| Parameter | Default | Description |
| --- | ---: | --- |
| `ADDR_WIDTH` | 32 | Width of source and destination byte addresses. |
| `DATA_WIDTH` | 32 | Width of memory data. Must remain 32 for this IP. |
| `THREAD_COUNT` | 4 | Number of independently programmable DMA threads. The 8-bit CSR address map supports up to 8 threads with the default 32-byte stride. |
| `MAX_OUTSTANDING_READS` | 4 | Global maximum accepted read requests waiting for read responses. |
| `MAX_OUTSTANDING_WRITES` | 4 | Global maximum accepted write requests waiting for write responses. |
| `MAX_TRANSFER_WORDS` | 4096 | Maximum legal transfer length for one thread descriptor. |
| `ID_WIDTH` | Derived | Width of memory transaction IDs. Defaults to enough bits for all shared ID slots. |
| `THREAD_ID_WIDTH` | Derived | Width needed to identify a DMA thread internally. |

## Register Map

Each thread owns a 32-byte CSR window:

`thread_base = thread_id * 0x20`

All registers are 32-bit wide.

| Offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `SRC_ADDR` | RW | Source byte address for this thread. |
| `0x04` | `DST_ADDR` | RW | Destination byte address for this thread. |
| `0x08` | `LEN_WORDS` | RW | Transfer length in 32-bit words. |
| `0x0C` | `CTRL` | RW | Bit 0: start. Bit 1: interrupt enable. |
| `0x10` | `STATUS` | RO/W1C | Bit 0: busy. Bit 1: done. Bit 2: error. |
| `0x14` | `WORDS_DONE` | RO | Number of completed write responses for the current or most recent descriptor. |

Writing `1` to `STATUS.done` or `STATUS.error` clears the corresponding sticky
status bit for that thread only. Writes to `WORDS_DONE` are illegal and set that
thread's `STATUS.error`.

## CSR Addressing

The 8-bit `cfg_addr` is decoded as:

- `cfg_addr[7:5]`: thread index.
- `cfg_addr[4:0]`: register offset inside the thread window.

For example, thread 2 `LEN_WORDS` is at `0x48`.

Accesses to unimplemented offsets set `STATUS.error` for the addressed thread.
Accesses to an invalid thread window return zero on reads and set thread 0
`STATUS.error`.

## Memory Interface

The memory interface matches the baseline DMA:

| Signal | Direction | Description |
| --- | --- | --- |
| `rd_req_valid` | Output | Read request valid. |
| `rd_req_ready` | Input | Read request accepted. |
| `rd_req_id` | Output | Shared-pool read transaction ID. |
| `rd_req_addr` | Output | Read byte address. |
| `rd_rsp_valid` | Input | Read response valid. |
| `rd_rsp_ready` | Output | DMA can accept read response. |
| `rd_rsp_id` | Input | Read response transaction ID. |
| `rd_rsp_data` | Input | Read response data. |
| `wr_req_valid` | Output | Write request valid. |
| `wr_req_ready` | Input | Write request accepted. |
| `wr_req_id` | Output | Shared-pool write transaction ID. |
| `wr_req_addr` | Output | Write byte address. |
| `wr_req_data` | Output | Write data. |
| `wr_rsp_valid` | Input | Write response valid. |
| `wr_rsp_ready` | Output | DMA can accept write response. |
| `wr_rsp_id` | Input | Write response transaction ID. |

Read and write responses may return out of order. The memory system must return
the same ID supplied on the corresponding request. The DMA asserts response ready
only for IDs that currently match an outstanding transaction of the expected
type.

## Operation

1. Software programs one or more thread CSR windows.
2. Software starts any subset of threads by writing `CTRL.start = 1`.
3. Each accepted nonzero descriptor sets that thread's `STATUS.busy`.
4. The top level arbitrates active threads in round-robin order and issues read
   requests while global read credit and shared ID slots are available.
5. The shared ID pool allocates one ID for every accepted read request. The ID is
   not freed until the matching write response completes.
6. The reorder buffer stores each allocated ID's destination address, read data,
   and owning thread.
7. A read response transitions its ID slot into write-pending state and reports
   the owning thread to the top level for per-thread outstanding count updates.
8. A write response frees the shared ID and increments `WORDS_DONE` for the
   owning thread.
9. A thread completes when its `WORDS_DONE` reaches `LEN_WORDS`; only that
   thread clears busy and sets done.

Starting a zero-length descriptor completes immediately for that thread without
issuing memory traffic.

## Descriptor Rules

Descriptor validation happens when software writes `CTRL.start = 1`.

For each thread:

- `LEN_WORDS` must be less than or equal to `MAX_TRANSFER_WORDS`.
- For nonzero transfers, the source and destination ranges must not overlap.
- The checked ranges are half-open intervals:
  `[SRC_ADDR, SRC_ADDR + LEN_WORDS * 4)` and
  `[DST_ADDR, DST_ADDR + LEN_WORDS * 4)`.

The IP does not check for memory range overlap between different DMA threads.
Software is responsible for avoiding inter-thread memory hazards.

## Error Handling

An error is reported per thread when software:

- Starts a descriptor while that same thread is busy.
- Starts a descriptor with an over-limit length.
- Starts a descriptor whose source and destination ranges overlap.
- Writes `SRC_ADDR`, `DST_ADDR`, or `LEN_WORDS` while that same thread is busy.
- Writes `WORDS_DONE`.
- Accesses an unimplemented CSR offset in that thread window.

Errors are sticky until cleared by writing `1` to `STATUS.error`. `irq_error[n]`
asserts while thread `n` has both `STATUS.error` and `CTRL.irq_en` set.

Errors in one thread do not stop other active threads.

## Implementation Structure

- `multi_thread_dma` contains CSR decode, per-thread descriptor state, round-robin
  read issue arbitration, per-thread progress counters, and global outstanding
  read/write counters.
- `multi_thread_dma_id_pool` owns the shared transaction ID allocation bitmap.
  Reset clears the pool. Per-thread starts do not clear it.
- `multi_thread_dma_reorder_buffer` tracks every shared ID slot from read
  outstanding, to write pending, to write outstanding. Each slot stores its
  owning thread so completion accounting is per-thread even though memory IDs are
  shared globally.
