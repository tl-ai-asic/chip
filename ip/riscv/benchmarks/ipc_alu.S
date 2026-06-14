  .option norvc

  .section .text.init, "ax"
  .globl _start
_start:
  li x1, 4
  li x2, 5
  li x3, 6
  li x4, 7
  li x5, 8
  li x6, 9
  li x7, 10
  li x8, 11
  li x9, 12
  li x10, 13

  .globl workload_start
workload_start:
  .rept 50
    add  x11, x1, x4
    sub  x12, x2, x5
    xor  x13, x3, x6
    or   x14, x4, x7
    and  x15, x5, x8
    slt  x16, x6, x9
    sltu x17, x7, x10
    sll  x18, x8, x1
    srl  x19, x9, x2
    sra  x20, x10, x3
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
