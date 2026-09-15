/* Calls pick(20) and exits with the result. `tbl' is the global ir/gsym.c
 * indexes by a constant, so every element has a different value and a
 * displacement applied to the wrong one changes the answer:
 *
 *   tbl[1] = 20; tbl[3] = 20 + 100; return 120 - 4
 *
 * Same values as drivers/gsym.c. */
	.text
	.globl _start
_start:
	li	a0,20
	call	pick
	li	a7,93
	ecall

	.data
	.align 2
	.globl tbl
tbl:
	.word	4,0,100,0
