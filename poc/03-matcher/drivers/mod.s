/* Calls rem(-7,3) and exits with what it returned. Same arguments as
 * drivers/mod.c. C truncates toward zero, so -7 % 3 is -1, the branch fires
 * and the answer is -2; a __modsi3 that floored would produce 2 and take no
 * branch, which is a different number and not the same one by accident. */
	.text
	.globl _start
_start:
	li	a0,-7
	li	a1,3
	call	rem
	li	a7,93
	ecall
