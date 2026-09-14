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
 * __mulsi3 and __divsi3 are here because RV32I has no multiplier
 * (decision-003) and the rule table lowers MULI4/DIVI4 to calls on them. They
 * are deliberately naive: the real runtime library is task-007, and these
 * exist only so this PoC's test can close the loop.
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

/* ir/expr.c's global. This PoC selects instructions; it does not emit data
 * definitions, so the one global the corpus touches is defined here. */
	.data
	.globl g
	.align 2
g:
	.word	0
