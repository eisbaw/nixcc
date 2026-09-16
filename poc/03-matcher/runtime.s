/* RV32I scaffolding shared by every execution case, and nothing more.
 *
 * Why the suite executes the code instead of only assembling it: this project
 * has twice shipped a harness that reported PASS while measuring nothing.
 * "riscv32-none-elf-as accepted it" proves the text is syntactically RISC-V.
 * It does not prove the matcher picked rules that compute the right value,
 * that the frame offsets agree with one another, or that a value held in a
 * callee-saved register really survives a libcall. Running f() and checking
 * the number it returns proves all three at once.
 *
 * __mulsi3, __divsi3, __modsi3, __udivsi3 and __umodsi3 are here because RV32I
 * has no multiplier (decision-003) and the rule table lowers
 * MULI4/DIVI4/MODI4 and MULU4/DIVU4/MODU4 to calls on them. They are
 * deliberately naive: the real runtime library is task-007, and these exist
 * only so this PoC's test can close the loop.
 *
 * Only ONE multiply serves both signednesses: the low 32 bits of a product
 * are the same bits whichever way the operands are read. Divide and remainder
 * are not like that, which is why there are two of each.
 */

	.text

/* The extern ir/expr.c calls. h(a,b) = a + b, chosen so that a swapped or
 * dropped argument register changes the answer. drivers/expr.c defines the
 * same function for the host build; they must agree. */
	.globl h
h:
	add	a0,a0,a1
	ret

/* a0 * a1, low 32 bits. Shift-and-add, consuming a1 as a bit pattern -- which
 * is correct for the low half of the product whatever the signs are. */
	.globl __mulsi3
__mulsi3:
	mv	t0,zero
1:	beqz	a1,2f
	andi	t1,a1,1
	beqz	t1,3f
	add	t0,t0,a0
3:	slli	a0,a0,1
	srli	a1,a1,1
	j	1b
2:	mv	a0,t0
	ret

/* a0 / a1, truncating toward zero as C requires: restoring division over the
 * magnitudes with the sign applied afterwards. Division by zero is not
 * handled -- it is undefined in C and no case exercises it. */
	.globl __divsi3
__divsi3:
	mv	t2,zero			/* sign of the quotient */
	bgez	a0,1f
	neg	a0,a0
	xori	t2,t2,1
1:	bgez	a1,2f
	neg	a1,a1
	xori	t2,t2,1
2:	mv	t0,zero			/* quotient  */
	mv	t1,zero			/* remainder */
	li	t3,32
3:	slli	t1,t1,1
	srli	t4,a0,31
	or	t1,t1,t4
	slli	a0,a0,1
	slli	t0,t0,1
	bltu	t1,a1,4f
	sub	t1,t1,a1
	ori	t0,t0,1
4:	addi	t3,t3,-1
	bnez	t3,3b
	beqz	t2,5f
	neg	t0,t0
5:	mv	a0,t0
	ret

/* a0 % a1, taking its sign from the dividend as C requires: -7 % 3 is -1,
 * not 2. Same restoring division as __divsi3, keeping the remainder instead
 * of the quotient. */
	.globl __modsi3
__modsi3:
	mv	t2,zero			/* sign of the dividend */
	bgez	a0,1f
	neg	a0,a0
	li	t2,1
1:	bgez	a1,2f
	neg	a1,a1
2:	mv	t1,zero			/* remainder */
	li	t3,32
3:	slli	t1,t1,1
	srli	t4,a0,31
	or	t1,t1,t4
	slli	a0,a0,1
	bltu	t1,a1,4f
	sub	t1,t1,a1
4:	addi	t3,t3,-1
	bnez	t3,3b
	beqz	t2,5f
	neg	t1,t1
5:	mv	a0,t1
	ret

/* a0 / a1, both read as 32-bit magnitudes: __divsi3's restoring loop with the
 * sign handling taken off and nothing else added. Instruction for instruction
 * the loop below IS __divsi3's, `bltu' included -- what differs is the range
 * of operands it now has to be right over, because __divsi3 only ever enters
 * its loop on magnitudes.
 *
 * That makes `bltu' the instruction to read twice. It is right here for the
 * same reason it is right there, but here it is also the only thing standing
 * between this routine and a wrong answer: a `blt' reads a divisor with bit 31
 * set as negative, so `t1 < a1' is false at every iteration, the subtract is
 * taken every time instead of never, and the quotient saturates to 0xffffffff.
 * That is what drivers/udiv.s's divisor is for, and what the mutation in
 * run.sh makes happen.
 *
 * `slli t1,t1,1' CANNOT CARRY OUT, which is worth writing down because the
 * obvious worry is that it can: the divisor may be as large as 2^32-1 here.
 * After k iterations the remainder is the top k bits of the dividend reduced
 * modulo the divisor, so it is below 2^k -- for every k <= 31 that is below
 * 2^31 whatever the divisor is, and doubling it stays inside 32 bits. The
 * 32nd iteration's shift is the last one; nothing doubles the remainder
 * again. An earlier version of this routine caught the carried bit in a
 * register first; the argument above says that bit is never set, and an
 * instruction-for-instruction simulation over 400000 random operand pairs
 * found it set zero times. It was dead code, and it went.
 *
 * Thirty-two fixed iterations, like __divsi3, so a zero divisor terminates
 * with a garbage answer rather than looping. Division by zero is undefined in
 * C and no case exercises it. Task-007 owns the real runtime library; these
 * exist so that DIVU4 and MODU4 have something to call. */
	.globl __udivsi3
__udivsi3:
	mv	t0,zero			/* quotient  */
	mv	t1,zero			/* remainder */
	li	t3,32
1:	slli	t1,t1,1
	srli	t4,a0,31
	or	t1,t1,t4
	slli	a0,a0,1
	slli	t0,t0,1
	bltu	t1,a1,2f
	sub	t1,t1,a1
	ori	t0,t0,1
2:	addi	t3,t3,-1
	bnez	t3,1b
	mv	a0,t0
	ret

/* a0 % a1, both unsigned: the same loop, keeping the remainder instead of the
 * quotient. There is no sign to apply, and that is the whole difference from
 * __modsi3 -- which is why -7 % 3 and 0xfffffff9 % 3 are different questions
 * with different answers. */
	.globl __umodsi3
__umodsi3:
	mv	t1,zero			/* remainder */
	li	t3,32
1:	slli	t1,t1,1
	srli	t4,a0,31
	or	t1,t1,t4
	slli	a0,a0,1
	bltu	t1,a1,2f
	sub	t1,t1,a1
2:	addi	t3,t3,-1
	bnez	t3,1b
	mv	a0,t1
	ret

/* ir/expr.c's global. This PoC selects instructions; it does not emit data
 * definitions, so the one global the corpus touches is defined here. */
	.data
	.globl g
	.align 2
g:
	.word	0
