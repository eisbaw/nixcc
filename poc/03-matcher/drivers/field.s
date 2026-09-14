/* Calls dist(&pt) and exits with the difference. Same field values as
 * drivers/field.c. x and y differ so that a wrong struct displacement -- the
 * addressing-mode fold this case exists to exercise -- changes the answer. */
	.text
	.globl _start
_start:
	la	a0,pt
	call	dist
	li	a7,93
	ecall

	.data
	.align 2
pt:
	.word	11,40
