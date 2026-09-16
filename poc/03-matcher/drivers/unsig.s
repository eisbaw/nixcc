/* Calls wide(0xfffffff0,9) and exits with what it returned. Same arguments and
 * the same uh()/uhook as drivers/unsig.c.
 *
 * BOTH OPERANDS ARE CHOSEN, and for different reasons. The dividend has bit 31
 * set, so read as a signed integer it is -16: __divsi3, __modsi3, `sra', `blt'
 * and `bge' each answer this program differently from __udivsi3, __umodsi3,
 * `srl', `bltu' and `bgeu'. On any operand below 2^31 the two sets agree and
 * this case would prove nothing. The divisor is 9 rather than 7 for the reason
 * ir/unsig.c's header gives at length -- with 7 the divide substitution was
 * measured to leave the answer unmoved.
 *
 * What this file does NOT reach is a DIVISOR above 2^31, which is what the
 * `bltu' inside the runtime routines turns on. ir/udiv.c is that case.
 *
 * uh(a,b) = a + b, the same addition h() does, so that a U-typed ARG, CALL and
 * RET have something to reach. `uhook' points at it, which is the only way C
 * reaches the indirect CALLU4 rows.
 */
	.text
	.globl _start
_start:
	li	a0,0xfffffff0
	li	a1,9
	call	wide
	li	a7,93
	ecall

	.globl uh
uh:
	add	a0,a0,a1
	ret

	.data
	.align	2
	.globl uhook
uhook:
	.word	uh
