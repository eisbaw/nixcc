/* Branches at exactly the limits of a B-type offset: +4092 forwards (the
 * largest even offset whose target can still be followed by an instruction)
 * and -4096 backwards, which is the field's minimum. One byte further either
 * way is a must-fail case; see must-fail.nix.
 */
	.text
	.globl _start
_start:
	beq	a0,a1,fardown		/* +4092 */
	.zero	4088
fardown:
	nop
	.zero	4092
	bge	a0,a1,fardown		/* -4096, the minimum a B-type reaches */
	j	_start
	ret
