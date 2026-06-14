  .option norvc

  .section .text.init, "ax"
  .globl _start
_start:
  lui x1, %hi(load_data)
  addi x1, x1, %lo(load_data)
  lui x6, %hi(store_data)
  addi x6, x6, %lo(store_data)
  li x2, 13
  li x3, 14
  li x4, 15
  li x5, 16
  li x7, 19
  li x8, 23
  li x9, 29
  li x10, 31

  .globl workload_start
workload_start:
  .set bench_offset, 0
  .rept 25
    add x11, x2, x3
    lw  x21, bench_offset + 0(x1)
    mul x16, x7, x8
    sw  x2, bench_offset + 0(x6)
    add x12, x3, x4
    lw  x22, bench_offset + 4(x1)
    mul x17, x8, x9
    sw  x3, bench_offset + 4(x6)
    add x13, x4, x5
    lw  x23, bench_offset + 8(x1)
    mul x18, x9, x10
    sw  x4, bench_offset + 8(x6)
    add x14, x5, x2
    lw  x24, bench_offset + 12(x1)
    mul x19, x10, x7
    sw  x5, bench_offset + 12(x6)
    add x15, x2, x4
    lw  x25, bench_offset + 16(x1)
    mul x20, x7, x9
    sw  x2, bench_offset + 16(x6)
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
  .set data_value, 0x2000
  .rept 125
    .word data_value
    .set data_value, data_value + 1
  .endr
store_data:
  .zero 512
