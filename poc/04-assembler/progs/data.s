/* Data items and alignment, including the two things an assembler gets
 * quietly wrong: that .word is NOT auto-aligned (the three bytes below leave
 * it unaligned until an explicit .align), and that padding in a code section
 * is nops once it reaches a word boundary and zeros before that.
 */
	.text
	.globl _start
_start:
	.byte	1,2,3
	.align	2
	.word	0xdeadbeef, 0x11223344
	.half	0x1234, 0x5678
	.byte	0xff
	.align	2
	.word	here			/* a symbol's absolute address, not a displacement */
here:
	nop
	.align	4
	.word	7
	.zero	6
	.align	1
	.half	9
