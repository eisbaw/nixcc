/* Calls walk(2) and exits with `hold' plus the byte the returned pointer
 * points at. TWO INDEPENDENT ANSWERS, added: `hold' is the whole integer
 * computation and the returned pointer is `tag + n + 4', so a defect in the
 * arithmetic cannot cancel against a defect in the return.
 *
 *   hold = 103334, tag[2+4] = 64, so 103398.
 *
 * Same values and the same take() as drivers/ptr.c. `tag' holds eight
 * DIFFERENT bytes so that a pointer off by one element reads a different
 * number rather than the same one twice. */
	.text
	.globl _start
_start:
	li	a0,2
	call	walk
	lb	t1,0(a0)
	la	t0,hold
	lw	a0,0(t0)
	add	a0,a0,t1
	li	a7,93
	ecall

/* take(s, n): s[0] * 10 + n. Written as two shifts and an add because RV32I
 * has no multiplier (decision-003) and this stub is hand-written assembly,
 * not something the matcher compiled. */
	.globl take
take:
	lb	t0,0(a0)
	slli	t1,t0,3
	slli	t2,t0,1
	add	t1,t1,t2
	add	a0,t1,a1
	ret

	.data
	.align	2
	.globl hold
hold:
	.word	0
	.globl tag
tag:
	.byte	1,2,4,8,16,32,64,100
