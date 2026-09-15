/* The PC-relative base, pinned.
 *
 * Every offset here is chosen so that computing it from the NEXT
 * instruction's address instead of the branch's own -- the classic
 * off-by-one-instruction bug -- changes the encoded word. A branch to itself
 * is offset 0 and becomes -4; the forward branch is +8 and becomes +4; the
 * backward one is -4 and becomes -8. None of them would look wrong.
 *
 * Assembled and diffed only. `self' branches to itself, so running it would
 * spin; the executable oracle is poc/03-matcher's corpus, run in the emulator.
 */
	.text
	.globl _start
_start:
self:
	beq	a0,a1,self		/* offset 0: the branch's own address */
	bne	a0,a1,over		/* offset +8: skips exactly one instruction */
	addi	a0,a0,1
over:
back:
	addi	a0,a0,2
	blt	a0,a1,back		/* offset -4: the instruction just before */
	jal	ra,self			/* J-type, backwards */
	j	fwd			/* J-type, forwards */
	nop
fwd:
	call	self			/* auipc pair, backwards */
here:
	la	t1,here			/* auipc pair, delta 0: auipc 0 / addi 0 */
	la	t2,fwd
	ret
