/* Calls mask(-1234,5678) and exits with what it returned. Same arguments as
 * drivers/bits.c.
 *
 * `a' is negative so that the operators run over a value with bit 31 set: the
 * masks and the two unary rules would all agree with a wrong implementation on
 * small positive operands, and `~x' followed by `-x' over a value near zero is
 * the one place a table that emitted nothing at all still looks plausible. */
	.text
	.globl _start
_start:
	li	a0,-1234
	li	a1,5678
	call	mask
	li	a7,93
	ecall
