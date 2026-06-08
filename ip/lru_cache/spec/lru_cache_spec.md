# LRU Cache IP Specification

## Overview

The LRU cache IP is a small set-associative cache between a single CPU-side
requester and a single backing memory target. It uses ready/valid handshakes on
both sides and tracks exact least-recently-used replacement state per set.

The baseline design uses one data word per cache line. Reads allocate on miss.
Writes are write-through and do not allocate on miss.

## Features

- Parameterized address width, data width, set count, and way count.
- Exact per-set LRU replacement.
- Read hit response without backing memory traffic.
- Read miss fetches one word from backing memory and fills the selected victim
  way.
- Write-through updates backing memory for every write.
- Write hits update the cached word after the backing memory acknowledges the
  write.
- Write misses bypass the cache and do not allocate.
- Byte write strobes for partial-word writes.
- One CPU transaction in flight at a time.

## Parameters

| Parameter | Default | Description |
| --- | ---: | --- |
| `ADDR_WIDTH` | 32 | Byte address width. |
| `DATA_WIDTH` | 32 | Data width. Must be byte-addressable with a power-of-two byte count of at least 2. |
| `SET_COUNT` | 16 | Number of cache sets. Must be a power of two and at least 2. |
| `WAY_COUNT` | 4 | Number of ways per set. Must be at least 2. |
| `SET_INDEX_WIDTH` | Derived | Width of set index. |
| `WAY_INDEX_WIDTH` | Derived | Width of way index. |
| `DATA_BYTES` | Derived | Number of bytes per cache word. |
| `BYTE_OFFSET_WIDTH` | Derived | Number of byte offset bits inside a word. |
| `TAG_WIDTH` | Derived | Width of tag stored in each way. |

## Address Format

The CPU and memory interfaces use byte addresses.

| Field | Bits | Description |
| --- | --- | --- |
| Tag | `ADDR_WIDTH-1 : BYTE_OFFSET_WIDTH+SET_INDEX_WIDTH` | Stored per valid way. |
| Set index | `BYTE_OFFSET_WIDTH+SET_INDEX_WIDTH-1 : BYTE_OFFSET_WIDTH` | Selects the cache set. |
| Byte offset | `BYTE_OFFSET_WIDTH-1 : 0` | Selects a byte within the cached word. |

Backing memory requests are aligned to the cached word size by clearing the byte
offset bits.

For writes, `cpu_req_wstrb` selects byte lanes within the aligned cached word.
The byte offset is used for tag/set decode but does not shift the write strobe or
write data.

## CPU Interface

| Signal | Direction | Description |
| --- | --- | --- |
| `cpu_req_valid` | Input | CPU request valid. |
| `cpu_req_ready` | Output | Cache can accept a request. |
| `cpu_req_write` | Input | `1` for write, `0` for read. |
| `cpu_req_addr` | Input | Byte address. |
| `cpu_req_wdata` | Input | Write data. |
| `cpu_req_wstrb` | Input | Byte write strobes. Ignored for reads. |
| `cpu_rsp_valid` | Output | Response valid. |
| `cpu_rsp_ready` | Input | CPU can accept the response. |
| `cpu_rsp_rdata` | Output | Read data. Zero for write responses. |
| `cpu_rsp_hit` | Output | `1` if the accepted CPU request hit in the cache. |
| `cpu_rsp_error` | Output | Backing memory error for the request. |

The cache accepts one CPU request at a time. `cpu_req_ready` is asserted only
when no miss, write, or unconsumed response is pending.

## Memory Interface

| Signal | Direction | Description |
| --- | --- | --- |
| `mem_req_valid` | Output | Backing memory request valid. |
| `mem_req_ready` | Input | Backing memory request accepted. |
| `mem_req_write` | Output | `1` for write, `0` for read. |
| `mem_req_addr` | Output | Word-aligned byte address. |
| `mem_req_wdata` | Output | Write data. |
| `mem_req_wstrb` | Output | Byte write strobes. |
| `mem_rsp_valid` | Input | Backing memory response valid. |
| `mem_rsp_ready` | Output | Cache can accept the response. |
| `mem_rsp_rdata` | Input | Read response data. Ignored for writes. |
| `mem_rsp_error` | Input | Memory error indication. |

Every memory request receives exactly one memory response. The cache does not
issue another memory request while waiting for that response.

## Operation

### Read Hit

1. The cache accepts the CPU read request.
2. The selected set is searched for a valid way with a matching tag.
3. The cached word is returned with `cpu_rsp_hit = 1`.
4. The hit way is moved to the most-recently-used position in that set's LRU
   order.

### Read Miss

1. The selected set is searched and no matching valid way is found.
2. The cache chooses a fill way. Invalid ways are preferred before replacing a
   valid line. If all ways are valid, the least-recently-used way is selected.
3. A backing memory read is issued for the aligned word address.
4. On a successful memory response, the selected way is filled with the returned
   data and request tag, marked valid, and moved to most-recently-used.
5. The returned memory data is forwarded to the CPU with `cpu_rsp_hit = 0`.

If the memory read returns `mem_rsp_error`, the CPU response reports the error
and the cache line is not filled.

### Write Hit

1. The cache accepts the CPU write request and merges `cpu_req_wdata` into the
   cached word using `cpu_req_wstrb`.
2. A backing memory write is issued with the merged word and original strobes.
3. On a successful memory response, the cached word is updated and the hit way is
   moved to most-recently-used.
4. The CPU receives a write response with `cpu_rsp_hit = 1`.

If the backing memory write returns `mem_rsp_error`, the CPU response reports the
error and the cached word is not modified.

### Write Miss

1. The cache accepts the CPU write request and finds no matching valid way.
2. A backing memory write is issued with `cpu_req_wdata` and `cpu_req_wstrb`.
3. The CPU receives a write response with `cpu_rsp_hit = 0`.
4. The cache does not allocate a line for the write miss.

## LRU Algorithm

Each set stores an ordered list of way IDs:

- Entry 0 is the most recently used way.
- Entry `WAY_COUNT-1` is the least recently used way.

On every successful cache access that touches a line, the accessed way is moved
to entry 0 and the previously more-recent entries shift down by one position.
On a read miss fill, the chosen victim way is moved to entry 0 after the fill
completes successfully. Invalid ways can be selected before the LRU way, but the
same move-to-front update is used after the fill.

## Error Handling

The cache propagates backing memory errors through `cpu_rsp_error`. Memory errors
do not invalidate existing cache state and do not update or fill cache lines.

The RTL includes simulation-time parameter assertions for unsupported
configurations.

## Limitations

- One-word cache lines only.
- One CPU transaction in flight.
- No dirty state and no write-back mode.
- Write misses do not allocate.
- No flush, invalidate, or CSR control interface.
