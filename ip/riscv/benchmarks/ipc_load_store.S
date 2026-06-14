  .option norvc

  .section .text.init, "ax"
  .globl _start
_start:
  lui x1, %hi(load_data)
  addi x1, x1, %lo(load_data)
  lui x6, %hi(store_data)
  addi x6, x6, %lo(store_data)
  li x11, 34
  li x12, 35
  li x13, 36
  li x14, 37
  li x15, 38

  .globl workload_start
workload_start:
  .set bench_offset, 0
  .rept 50
    lw x21, bench_offset + 0(x1)
    sw x11, bench_offset + 0(x6)
    lw x22, bench_offset + 4(x1)
    sw x12, bench_offset + 4(x6)
    lw x23, bench_offset + 8(x1)
    sw x13, bench_offset + 8(x6)
    lw x24, bench_offset + 12(x1)
    sw x14, bench_offset + 12(x6)
    lw x25, bench_offset + 16(x1)
    sw x15, bench_offset + 16(x6)
    .set bench_offset, bench_offset + 20
  .endr
  .globl workload_end
workload_end:
  fence
  lui x5, %hi(tohost)
  addi x5, x5, %lo(tohost)
  li x6, 1
  sw x6, 0(x5)
1:
  j 1b

  .section .tohost, "aw"
  .align 3
  .globl tohost
tohost:
  .dword 0
  .globl fromhost
fromhost:
  .dword 0

  .section .data, "aw"
  .align 2
load_data:
  .set data_value, 0x1000
  .rept 250
    .word data_value
    .set data_value, data_value + 1
  .endr
store_data:
  .zero 1024
