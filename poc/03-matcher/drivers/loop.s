/* Calls sum(vec, 5) and exits with the total. Same vector and length as
 * drivers/loop.c. The negative element is there so a sign-extension or an
 * unsigned-compare mistake in the emitted loop changes the answer. */
	.text
	.globl _start
_start:
	la	a0,vec
	li	a1,5
	call	sum
	li	a7,93
	ecall

	.data
	.align 2
vec:
	.word	3,-1,10,7,100
