/* Calls pack(1) and exits with the result. The array is filled from the
 * argument, so 1 here and 1 in drivers/lbuf.c are the same fact stated twice
 * on purpose -- the two oracles have to be asked the same question.
 *
 *   buf[i] = i + 1 for i in 0..7, then buf[3] = 100 and buf[5] = 7
 *   1 + 100*2 + 7*4 + 8*8 = 293
 */
	.text
	.globl _start
_start:
	li	a0,1
	call	pack
	li	a7,93
	ecall
