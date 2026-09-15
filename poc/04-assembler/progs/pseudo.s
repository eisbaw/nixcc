/* Every mnemonic this assembler implements that the other programs do not
 * already reach, so the differential against GNU as covers the whole table
 * rather than the part the corpus happened to use. check.nix fails if a
 * mnemonic exists with no occurrence anywhere in progs/.
 *
 * The four swapping pseudo-branches (bgt, ble, bgtu, bleu) are the reason
 * this file is worth its length: they are `blt'/`bge' with the operands
 * REVERSED, and getting that backwards still assembles and still runs, just
 * comparing the wrong way round.
 */
	.text
	.globl _start
_start:
	add	a0,a1,a2
	sub	a0,a1,a2
	sll	a0,a1,a2
	slt	a0,a1,a2
	sltu	a0,a1,a2
	xor	a0,a1,a2
	srl	a0,a1,a2
	sra	a0,a1,a2
	or	a0,a1,a2
	and	a0,a1,a2
	slti	a0,a1,-7
	sltiu	a0,a1,7
	xori	a0,a1,-1
	ori	a0,a1,255
	andi	a0,a1,-256
	slli	a0,a1,31
	srli	a0,a1,1
	srai	a0,a1,17
	lb	a0,-4(s0)
	lh	a0,0(s0)
	lw	a0,2047(s0)
	lbu	a0,-2048(s0)
	lhu	a0,8(sp)
	sb	a0,-4(s0)
	sh	a0,0(s0)
	sw	a0,-60(s0)
	lui	a0,524288
	auipc	a0,1
	jalr	ra,a0,16
	jalr	a0
	jr	a0
	ecall
	ebreak
	fence
	nop
	mv	a0,a1
	not	a0,a1
	neg	a0,a1
	seqz	a0,a1
	snez	a0,a1
	sltz	a0,a1
	sgtz	a0,a1
target:
	beqz	a0,target
	bnez	a0,target
	bgez	a0,target
	bltz	a0,target
	blez	a0,target
	bgtz	a0,target
	bgt	a0,a1,target
	ble	a0,a1,target
	bgtu	a0,a1,target
	bleu	a0,a1,target
	bltu	a0,a1,target
	bgeu	a0,a1,target
	jal	target
	tail	target
	tail	far
	li	a0,0
	ret
1:
	nop
	j	1b
	j	1f
	nop
1:
	nop
far:
	ret
