# One source of truth for the encoder test: each case carries the GNU-as text
# and the equivalent Nix encoder call. `asm` is fed to riscv32-none-elf-as and
# `word` is what our encoder produced; the harness diffs them.
let
  e = import ./encode.nix;
  c = asm: word: { inherit asm word; };
in [
  # I-type, including the negative-immediate path
  (c "addi a0, a1, 5"        (e.addi "a0" "a1" 5))
  (c "addi a0, a1, -5"       (e.addi "a0" "a1" (-5)))
  (c "addi x0, x0, 0"        (e.addi "x0" "x0" 0))
  (c "addi t0, sp, 2047"     (e.addi "t0" "sp" 2047))
  (c "addi t0, sp, -2048"    (e.addi "t0" "sp" (-2048)))
  (c "xori a3, a4, -1"       (e.xori "a3" "a4" (-1)))
  (c "andi s0, s1, 255"      (e.andi "s0" "s1" 255))
  (c "sltiu a0, a0, 1"       (e.sltiu "a0" "a0" 1))
  # R-type
  (c "add a0, a1, a2"        (e.add "a0" "a1" "a2"))
  (c "sub s2, s3, s4"        (e.sub "s2" "s3" "s4"))
  (c "and t0, t1, t2"        (e.and "t0" "t1" "t2"))
  (c "or ra, sp, gp"         (e.or "ra" "sp" "gp"))
  (c "xor x31, x30, x29"     (e.xor 31 30 29))
  (c "sll a0, a1, a2"        (e.sll "a0" "a1" "a2"))
  (c "sra a0, a1, a2"        (e.sra "a0" "a1" "a2"))
  (c "slt a0, a1, a2"        (e.slt "a0" "a1" "a2"))
  # shift-immediate (funct7 discriminates srli/srai)
  (c "slli a0, a1, 0"        (e.slli "a0" "a1" 0))
  (c "slli a0, a1, 31"       (e.slli "a0" "a1" 31))
  (c "srli a0, a1, 1"        (e.srli "a0" "a1" 1))
  (c "srai a0, a1, 31"       (e.srai "a0" "a1" 31))
  # loads / stores, negative offsets exercise the split S-type immediate
  (c "lw a0, 0(sp)"          (e.lw "a0" "sp" 0))
  (c "lw a0, -4(sp)"         (e.lw "a0" "sp" (-4)))
  (c "lb a1, 2047(gp)"       (e.lb "a1" "gp" 2047))
  (c "lbu a1, -2048(gp)"     (e.lbu "a1" "gp" (-2048)))
  (c "sw a0, 0(sp)"          (e.sw "sp" "a0" 0))
  (c "sw ra, -4(sp)"         (e.sw "sp" "ra" (-4)))
  (c "sb a2, 1(a3)"          (e.sb "a3" "a2" 1))
  (c "sh a2, -1(a3)"         (e.sh "a3" "a2" (-1)))
  # B-type: the shuffled, scaled-by-2 immediate is the classic encoding trap
  (c "beq a0, a1, ."         (e.beq "a0" "a1" 0))
  (c "bne a0, a1, .+4"       (e.bne "a0" "a1" 4))
  (c "blt a0, a1, .-4"       (e.blt "a0" "a1" (-4)))
  (c "bge a0, a1, .+2046"    (e.bge "a0" "a1" 2046))
  (c "bltu a0, a1, .-2048"   (e.bltu "a0" "a1" (-2048)))
  (c "bgeu a0, a1, .+4094"   (e.bgeu "a0" "a1" 4094))
  (c "beq a0, a1, .-4096"    (e.beq "a0" "a1" (-4096)))
  # U-type
  (c "lui a0, 0"             (e.lui "a0" 0))
  (c "lui a0, 1"             (e.lui "a0" 1))
  (c "lui a0, 0xfffff"       (e.lui "a0" 1048575))
  (c "auipc ra, 0x12345"     (e.auipc "ra" 74565))
  # J-type: another shuffled immediate
  (c "jal ra, ."             (e.jal "ra" 0))
  (c "jal ra, .+4"           (e.jal "ra" 4))
  (c "jal x0, .-4"           (e.jal "x0" (-4)))
  (c "jal ra, .+1048574"     (e.jal "ra" 1048574))
  (c "jal ra, .-1048576"     (e.jal "ra" (-1048576)))
  (c "jalr ra, 0(a0)"        (e.jalr "ra" "a0" 0))
  (c "jalr x0, -8(ra)"       (e.jalr "x0" "ra" (-8)))
  # system
  (c "ecall"                 e.ecall)
  (c "ebreak"                e.ebreak)
]
