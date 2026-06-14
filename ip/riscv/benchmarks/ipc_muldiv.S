  .option norvc

  .section .text.init, "ax"
  .globl _start
_start:
  li x1, 18
  li x2, 19
  li x3, 20
  li x4, 21
  li x5, 22
  li x6, 23
  li x7, 24
  li x8, 25
  li x9, 26
  li x10, 27

  .globl workload_start
workload_start:
  .rept 25
    mul    x11, x1, x2
    mulh   x12, x2, x3
    mulhu  x13, x3, x4
    mulhsu x14, x4, x5
    div    x15, x5, x6
    divu   x16, x6, x7
    rem    x17, x7, x8
    remu   x18, x8, x9
    mul    x19, x9, x10
    mulhu  x20, x10, x1
    mul    x21, x1, x3
    mulh   x22, x2, x4
    mulhu  x23, x3, x5
    mulhsu x24, x4, x6
    div    x25, x5, x7
    divu   x26, x6, x8
    rem    x27, x7, x9
    remu   x28, x8, x10
    mul    x29, x9, x1
    mulhu  x30, x10, x2
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
