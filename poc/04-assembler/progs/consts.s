/* lui/addi constant materialisation, value by value.
 *
 * The five the task names are first. 0x7ff is the largest that fits addi
 * alone; 0x800 is the smallest that does not, and is the case the +0x800
 * correction exists for; 0xfffff800 is -2048 and fits addi alone, so an
 * assembler that always emits lui+addi gets the LENGTH wrong here; -1 is the
 * all-ones case; 0x80000000 has a zero low half and is `lui' alone.
 */
	.text
	.globl _start
_start:
	li	a0,0x7ff
	li	a1,0x800
	li	a2,0xfffff800
	li	a3,-1
	li	a4,0x80000000
	li	a5,0
	li	a6,2047
	li	a7,-2048
	li	t0,-2049
	li	t1,2048
	li	t2,0x7fffffff
	li	t3,0xfffff7ff
	li	t4,0x12345678
	li	t5,4096
	li	t6,0xfffff000
	ret
