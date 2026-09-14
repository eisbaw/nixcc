/* Calls probe(5,9) and exits with what it returned. Same arguments as
 * drivers/cond.c. The two arms return different values, so a branch emitted
 * the wrong way round changes the answer rather than hiding. */
	.text
	.globl _start
_start:
	li	a0,5
	li	a1,9
	call	probe
	li	a7,93
	ecall
