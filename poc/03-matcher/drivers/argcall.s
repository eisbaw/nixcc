/* Calls nested(6) and exits with what it returned. Same argument as
 * drivers/argcall.c. The libcall in the first argument position runs before
 * anything is placed in a0, which is why this one is legal. */
	.text
	.globl _start
_start:
	li	a0,6
	call	nested
	li	a7,93
	ecall
