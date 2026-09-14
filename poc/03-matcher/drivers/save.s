/* Calls hold(6,7) and exits with what it returned. Same arguments as
 * drivers/save.c. */
	.text
	.globl _start
_start:
	li	a0,6
	li	a1,7
	call	hold
	li	a7,93
	ecall
