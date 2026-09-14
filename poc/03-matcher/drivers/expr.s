/* Calls f(7,3) and exits with what it returned, so the emulator's exit code is
 * the value the compiled function computed. Kept beside drivers/expr.c, which
 * must call f with the SAME arguments: the test is the two answers agreeing. */
	.text
	.globl _start
_start:
	li	a0,7
	li	a1,3
	call	f
	li	a7,93			/* exit(a0) */
	ecall
