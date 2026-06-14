  .option norvc

  .section .text.init, "ax"
  .globl _start
_start:
  lui x1, %hi(load_data)
  addi x1, x1, %lo(load_data)
  lui x2, %hi(store_data)
  addi x2, x2, %lo(store_data)
  li x3, 0x123
  li x4, 0x234
  li x5, 0x345
  li x6, 0x456
  li x7, 0x567
  li x8, 0x678
  li x9, 0x789
  li x10, 0x89a

  .globl workload_start
workload_start:
  xori  x11, x10, -71
  lb    x31, 108(x1)
  div   x11, x5, x9
  divu  x12, x10, x4
  sltu  x30, x9, x6
  sra   x29, x4, x9
  or    x19, x7, x4
  srai  x25, x5, 12
  sh    x9, 392(x2)
  mulh  x22, x9, x8
  sub   x18, x10, x7
  sb    x6, 176(x2)
  srai  x25, x5, 17
  addi  x29, x8, 52
  divu  x18, x9, x9
  and   x26, x6, x10
  sb    x3, 964(x2)
  lb    x23, 944(x1)
  div   x19, x6, x5
  mul   x30, x5, x9
  bgeu  x0, x4, workload_end
  srl   x23, x0, x5
  divu  x15, x3, x5
  xor   x13, x5, x3
  sw    x8, 908(x2)
  andi  x18, x10, 116
  ori   x18, x7, 55
  slt   x14, x4, x3
  or    x17, x6, x5
  addi  x12, x5, 32
  or    x30, x4, x7
  add   x29, x6, x7
  mulhsu x24, x10, x8
  slti  x21, x6, 55
  lh    x26, 412(x1)
  ori   x17, x9, 81
  mul   x30, x8, x7
  lhu   x25, 272(x1)
  or    x21, x8, x6
  xori  x13, x4, 92
  srli  x23, x6, 6
  beq   x0, x3, workload_end
  xor   x22, x9, x3
  mul   x28, x7, x8
  sw    x8, 1008(x2)
  slt   x15, x7, x8
  lb    x25, 980(x1)
  mulhsu x19, x6, x9
  remu  x13, x0, x3
  srl   x25, x4, x6
  add   x16, x10, x3
  sh    x6, 0(x2)
  lb    x17, 300(x1)
  and   x12, x7, x10
  slti  x25, x10, 56
  sll   x21, x9, x10
  sb    x9, 444(x2)
  addi  x11, x7, -26
  rem   x27, x7, x3
  slli  x26, x7, 11
  rem   x25, x5, x9
  sll   x20, x9, x6
  add   x24, x5, x5
  addi  x12, x8, -117
  remu  x23, x0, x4
  lh    x15, 612(x1)
  lbu   x25, 824(x1)
  sw    x10, 912(x2)
  slt   x22, x7, x10
  bne   x0, x0, workload_end
  srl   x17, x9, x7
  lh    x19, 412(x1)
  blt   x4, x0, workload_end
  srli  x20, x3, 23
  mulhu x21, x4, x3
  srai  x30, x3, 7
  sh    x9, 212(x2)
  sub   x25, x3, x6
  mulhsu x25, x7, x6
  divu  x13, x6, x6
  slt   x22, x5, x5
  remu  x16, x4, x10
  rem   x16, x0, x4
  sb    x6, 472(x2)
  lhu   x22, 604(x1)
  srl   x19, x0, x10
  slt   x24, x6, x6
  lw    x24, 204(x1)
  or    x23, x7, x6
  sub   x14, x5, x7
  sb    x5, 632(x2)
  sltiu x12, x3, 73
  mulh  x15, x7, x6
  ori   x27, x8, 75
  srli  x23, x7, 10
  slli  x18, x10, 15
  mulh  x29, x10, x3
  sub   x19, x10, x4
  sra   x23, x8, x5
  ori   x17, x5, -21
  beq   x0, x3, workload_end
  rem   x15, x9, x6
  lbu   x11, 428(x1)
  srai  x30, x0, 26
  div   x17, x10, x5
  xori  x29, x5, 51
  sh    x3, 588(x2)
  mulh  x29, x0, x6
  mulh  x20, x9, x7
  sll   x22, x9, x6
  ori   x21, x4, -78
  sltiu x27, x10, 46
  ori   x11, x4, -122
  sltiu x30, x9, 18
  andi  x13, x6, -42
  mulhsu x29, x10, x8
  sb    x5, 536(x2)
  lbu   x25, 832(x1)
  mulh  x14, x3, x8
  addi  x27, x6, -54
  and   x25, x7, x9
  lbu   x25, 248(x1)
  bltu  x4, x0, workload_end
  addi  x26, x8, -4
  sltu  x17, x9, x4
  sltiu x26, x7, 9
  xori  x14, x3, 58
  mulhsu x16, x7, x6
  mulh  x22, x7, x4
  addi  x28, x5, -75
  sra   x22, x7, x3
  slt   x30, x6, x4
  lw    x22, 24(x1)
  sw    x4, 640(x2)
  or    x18, x7, x10
  srli  x22, x7, 29
  sltiu x12, x9, 68
  addi  x30, x5, -74
  bne   x0, x0, workload_end
  sra   x31, x4, x4
  lhu   x26, 756(x1)
  rem   x17, x6, x4
  sw    x6, 860(x2)
  and   x17, x6, x4
  xori  x30, x0, 101
  lbu   x28, 424(x1)
  sub   x25, x0, x9
  lh    x27, 124(x1)
  srli  x22, x8, 30
  sub   x13, x7, x9
  sltiu x26, x10, -47
  sra   x12, x7, x4
  srai  x20, x6, 12
  srai  x19, x8, 2
  lh    x22, 280(x1)
  slti  x11, x4, 89
  remu  x15, x6, x8
  slti  x18, x9, 123
  lb    x16, 732(x1)
  or    x22, x4, x9
  mulhu x17, x7, x8
  slt   x21, x7, x9
  sltiu x17, x5, 97
  sh    x5, 52(x2)
  or    x20, x7, x10
  sub   x15, x7, x7
  lh    x31, 360(x1)
  mulh  x27, x8, x8
  bne   x0, x0, workload_end
  lhu   x27, 608(x1)
  addi  x14, x10, 110
  sb    x7, 252(x2)
  mul   x26, x4, x3
  slt   x26, x10, x5
  slli  x11, x6, 20
  and   x29, x6, x7
  lhu   x14, 864(x1)
  bge   x0, x4, workload_end
  sll   x31, x8, x6
  mul   x22, x7, x10
  mulhu x15, x0, x8
  sw    x10, 932(x2)
  sra   x16, x0, x10
  mulhu x12, x10, x6
  xori  x12, x8, -29
  divu  x31, x5, x9
  srl   x17, x7, x9
  beq   x0, x3, workload_end
  remu  x11, x3, x8
  slt   x12, x8, x5
  lh    x24, 112(x1)
  sra   x18, x0, x8
  sh    x8, 940(x2)
  add   x29, x5, x3
  sh    x4, 644(x2)
  ori   x17, x4, -17
  sb    x10, 884(x2)
  slti  x16, x9, 77
  div   x27, x8, x4
  ori   x24, x10, -17
  mulhsu x19, x9, x9
  slli  x31, x0, 19
  slli  x26, x0, 16
  lh    x24, 404(x1)
  mulhu x23, x5, x10
  bne   x0, x0, workload_end
  bltu  x4, x0, workload_end
  slli  x28, x3, 1
  slli  x11, x4, 17
  or    x30, x7, x10
  srli  x27, x8, 0
  sub   x12, x9, x6
  sw    x6, 888(x2)
  andi  x27, x8, 44
  lhu   x25, 728(x1)
  lh    x13, 856(x1)
  sra   x22, x3, x3
  addi  x26, x9, -49
  sltu  x16, x5, x6
  div   x19, x9, x7
  slli  x19, x7, 20
  or    x11, x0, x9
  divu  x20, x10, x8
  sh    x10, 276(x2)
  andi  x29, x0, 17
  and   x15, x3, x6
  sltiu x22, x6, -38
  sw    x10, 360(x2)
  sw    x4, 888(x2)
  mulhu x26, x7, x5
  xori  x19, x6, -66
  lh    x14, 384(x1)
  slt   x17, x8, x7
  lh    x26, 328(x1)
  sb    x10, 100(x2)
  srai  x25, x9, 20
  bne   x0, x0, workload_end
  xor   x24, x9, x6
  sh    x6, 836(x2)
  sltiu x21, x10, -60
  xor   x15, x7, x9
  xor   x28, x4, x10
  divu  x20, x6, x10
  andi  x18, x9, -42
  lw    x20, 628(x1)
  add   x20, x3, x9
  ori   x31, x5, -65
  div   x13, x6, x8
  lb    x27, 912(x1)
  addi  x12, x10, -24
  lb    x20, 760(x1)
  ori   x26, x8, 124
  lw    x18, 936(x1)
  srl   x31, x8, x7
  lw    x15, 512(x1)
  bge   x0, x4, workload_end
  add   x27, x6, x7
  lh    x20, 152(x1)
  lbu   x19, 324(x1)
  sub   x27, x5, x10
  lb    x30, 260(x1)
  sra   x18, x7, x4
  sltu  x29, x4, x6
  mulh  x23, x5, x5
  mulhsu x21, x0, x3
  addi  x13, x0, -44
  lb    x23, 196(x1)
  andi  x26, x3, 90
  slli  x19, x6, 7
  andi  x15, x5, -96
  sltu  x17, x8, x8
  sh    x10, 940(x2)
  xori  x24, x7, 54
  srai  x13, x9, 6
  mulhsu x20, x8, x9
  addi  x23, x4, -81
  blt   x4, x0, workload_end
  div   x26, x7, x8
  sw    x10, 600(x2)
  slt   x19, x3, x10
  mulhu x23, x6, x6
  lb    x15, 124(x1)
  lh    x11, 32(x1)
  sb    x9, 612(x2)
  remu  x25, x9, x7
  srli  x12, x7, 2
  andi  x26, x10, -72
  mulhsu x22, x5, x8
  sll   x11, x8, x4
  srli  x18, x9, 7
  or    x30, x7, x9
  rem   x22, x3, x9
  slt   x16, x10, x4
  slti  x26, x4, -52
  mulhsu x14, x9, x8
  sltiu x27, x4, 67
  slti  x15, x9, -79
  sb    x4, 428(x2)
  mulh  x23, x3, x7
  sll   x27, x6, x10
  ori   x25, x6, -105
  mulhsu x23, x5, x9
  mulhu x11, x9, x9
  lhu   x27, 124(x1)
  divu  x21, x8, x4
  lbu   x29, 764(x1)
  slli  x16, x7, 24
  xori  x23, x8, -114
  lb    x23, 260(x1)
  ori   x13, x3, -37
  divu  x16, x8, x10
  lw    x18, 308(x1)
  addi  x24, x4, 70
  mulhsu x18, x10, x9
  mulhsu x31, x3, x6
  add   x18, x8, x9
  sll   x25, x9, x4
  sll   x22, x7, x4
  xor   x29, x5, x3
  addi  x30, x4, -96
  slti  x17, x8, 77
  sra   x25, x3, x9
  mulh  x15, x6, x3
  sll   x25, x10, x10
  mul   x31, x6, x8
  sltu  x29, x10, x10
  and   x25, x7, x8
  srai  x29, x3, 3
  or    x26, x8, x10
  mulhsu x16, x7, x10
  sra   x24, x7, x9
  beq   x0, x3, workload_end
  xori  x16, x4, -26
  slt   x22, x8, x4
  add   x19, x8, x4
  mulhu x16, x10, x5
  sw    x7, 600(x2)
  div   x23, x10, x10
  mul   x16, x0, x8
  lbu   x29, 664(x1)
  sb    x5, 328(x2)
  add   x26, x6, x3
  add   x26, x4, x3
  sh    x10, 740(x2)
  add   x25, x5, x7
  rem   x24, x5, x8
  srli  x23, x8, 1
  lhu   x23, 728(x1)
  divu  x17, x3, x10
  or    x13, x7, x6
  blt   x4, x0, workload_end
  sltiu x13, x8, -83
  sb    x3, 460(x2)
  addi  x28, x7, -111
  sltu  x21, x10, x3
  remu  x31, x4, x3
  sw    x4, 84(x2)
  addi  x12, x8, 114
  mulhsu x26, x7, x9
  rem   x14, x10, x7
  slt   x24, x0, x5
  srai  x24, x9, 30
  ori   x25, x4, 12
  xori  x26, x0, -39
  ori   x23, x5, 28
  slli  x12, x0, 0
  remu  x22, x3, x3
  sb    x8, 784(x2)
  addi  x19, x6, 85
  div   x31, x5, x9
  srai  x26, x10, 9
  slli  x23, x3, 3
  sh    x7, 892(x2)
  sra   x20, x0, x8
  slt   x29, x9, x3
  sra   x12, x10, x6
  add   x26, x10, x10
  sltu  x15, x9, x8
  slli  x24, x8, 11
  andi  x19, x4, -111
  xor   x30, x9, x7
  xori  x18, x4, 91
  sll   x11, x7, x9
  lh    x22, 116(x1)
  andi  x25, x8, 75
  div   x11, x10, x5
  or    x17, x3, x7
  lbu   x17, 212(x1)
  add   x25, x8, x6
  xori  x14, x6, 10
  sll   x27, x4, x9
  sb    x7, 428(x2)
  sll   x18, x0, x8
  lbu   x30, 756(x1)
  mulhsu x28, x0, x5
  div   x25, x0, x5
  mulhsu x12, x4, x6
  slti  x27, x0, 1
  lb    x23, 572(x1)
  slti  x22, x10, -96
  div   x18, x4, x4
  sh    x8, 736(x2)
  divu  x24, x9, x3
  sw    x7, 52(x2)
  srl   x12, x9, x7
  srl   x25, x9, x7
  remu  x19, x9, x5
  divu  x19, x0, x10
  xor   x29, x8, x6
  sh    x10, 968(x2)
  andi  x29, x3, -11
  or    x14, x3, x3
  sh    x10, 532(x2)
  sw    x8, 808(x2)
  bltu  x4, x0, workload_end
  lh    x22, 448(x1)
  sh    x5, 308(x2)
  sh    x3, 980(x2)
  srl   x26, x6, x8
  mulhu x28, x7, x8
  srli  x18, x0, 19
  xori  x25, x3, 66
  sh    x7, 704(x2)
  div   x20, x6, x4
  srai  x13, x7, 10
  srai  x24, x8, 15
  sh    x6, 452(x2)
  div   x11, x7, x6
  srai  x28, x10, 4
  slti  x31, x10, -37
  slli  x28, x0, 1
  sh    x8, 816(x2)
  sltiu x18, x10, -57
  divu  x15, x5, x3
  xori  x12, x5, 57
  lh    x24, 472(x1)
  slti  x30, x4, 92
  lb    x23, 400(x1)
  ori   x27, x0, -122
  lhu   x19, 868(x1)
  ori   x21, x10, -51
  divu  x19, x6, x9
  sb    x6, 776(x2)
  and   x22, x9, x8
  lb    x21, 72(x1)
  xori  x23, x6, -36
  mulhu x16, x6, x6
  sub   x28, x0, x3
  ori   x21, x3, 116
  sb    x3, 64(x2)
  remu  x24, x10, x3
  sltiu x15, x4, 75
  lb    x14, 660(x1)
  lb    x21, 448(x1)
  ori   x16, x0, 19
  slli  x15, x7, 6
  slli  x25, x6, 11
  mulhsu x11, x8, x7
  or    x17, x4, x8
  lb    x18, 60(x1)
  blt   x4, x0, workload_end
  xor   x11, x4, x9
  sw    x3, 548(x2)
  mulh  x24, x0, x8
  lbu   x27, 48(x1)
  slti  x26, x10, -22
  sb    x6, 304(x2)
  slt   x21, x5, x4
  sra   x29, x4, x4
  xor   x15, x4, x3
  sltiu x24, x4, 101
  lb    x29, 832(x1)
  slt   x12, x7, x6
  lbu   x16, 244(x1)
  mulh  x31, x6, x9
  srai  x26, x5, 20
  lw    x21, 920(x1)
  slt   x24, x0, x6
  sll   x17, x5, x6
  divu  x21, x10, x6
  slti  x27, x10, -72
  divu  x11, x4, x7
  sltu  x22, x7, x8
  slti  x12, x8, -95
  add   x30, x9, x5
  slt   x27, x10, x5
  lh    x30, 720(x1)
  sltiu x26, x4, -74
  ori   x22, x7, 49
  sh    x3, 156(x2)
  sll   x23, x8, x9
  sb    x5, 468(x2)
  srli  x30, x9, 1
  srli  x22, x9, 13
  or    x20, x3, x10
  div   x19, x6, x4
  remu  x20, x6, x4
  or    x25, x4, x6
  mulhu x24, x4, x6
  bltu  x4, x0, workload_end
  .globl workload_end
workload_end:
  fence
  lui x5, %hi(tohost)
  addi x5, x5, %lo(tohost)
  li x6, 1
  sw x6, 0(x5)
  nop
  nop
  nop

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
  .zero 1024
store_data:
  .zero 1024
