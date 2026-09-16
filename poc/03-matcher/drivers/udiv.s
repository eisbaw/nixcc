/* Calls wrap(0xfffffffe,0x80000001) and exits with what it returned. Same
 * arguments as drivers/udiv.c.
 *
 * The DIVISOR is what matters here, and it is the only thing this case adds to
 * ir/unsig.c's dividend: 0x80000001 read as a signed integer is negative, so
 * if the `bltu' inside __udivsi3 and __umodsi3 were a `blt' the comparison
 * `remainder < divisor' would be false at every iteration and the subtract
 * would be taken every time instead of none. The quotient saturates to
 * 0xffffffff and the remainder comes out 0x7fffffff.
 *
 * 0xfffffffe / 0x80000001 is 1 and 0xfffffffe % 0x80000001 is 0x7ffffffd, so
 * the answer is 1 ^ 0x7ffffffd = 0x7ffffffc. A signed comparison in the loop
 * gives 0xffffffff ^ 0x7fffffff = 0x80000000 instead. Both numbers were read
 * off the emulator, not derived here.
 */
	.text
	.globl _start
_start:
	li	a0,0xfffffffe
	li	a1,0x80000001
	call	wrap
	li	a7,93
	ecall
