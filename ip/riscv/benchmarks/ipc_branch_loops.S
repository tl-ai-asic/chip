  .option norvc

  .section .text.init, "ax"
  .globl _start
_start:
  addi x1, x0, 3
  addi x2, x0, 5
  addi x3, x0, 7
  addi x12, x0, 0
  addi x15, x0, 0
  addi x19, x0, 0

  .globl workload_start
workload_start:
  addi x11, x0, 64
loop_a:
  add  x12, x12, x1
  addi x11, x11, -1
  bne  x11, x0, loop_a

  addi x13, x0, 16
outer_loop:
  addi x14, x0, 8
inner_loop:
  add  x15, x15, x2
  add  x16, x15, x12
  addi x14, x14, -1
  bne  x14, x0, inner_loop
  addi x13, x13, -1
  bne  x13, x0, outer_loop

  addi x18, x0, 32
loop_c:
  add  x19, x19, x3
  add  x20, x19, x12
  addi x18, x18, -1
  bne  x18, x0, loop_c
  .globl workload_end
workload_end:
  fence

  addi x21, x0, 192
  bne  x12, x21, fail
  addi x21, x0, 640
  bne  x15, x21, fail
  addi x21, x0, 224
  bne  x19, x21, fail

  lui x5, %hi(tohost)
  addi x5, x5, %lo(tohost)
  li x6, 1
  sw x6, 0(x5)
1:
  j 1b

fail:
  lui x5, %hi(tohost)
  addi x5, x5, %lo(tohost)
  li x6, 3
  sw x6, 0(x5)
2:
  j 2b

  .globl workload_expected_retired
  .equ workload_expected_retired, 883

  .section .tohost, "aw"
  .align 3
  .globl tohost
tohost:
  .dword 0
  .globl fromhost
fromhost:
  .dword 0
