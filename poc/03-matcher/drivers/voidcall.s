/* Calls emit(20) and exits with what put() accumulated, NOT with what emit()
 * returned. That is the point: emit() discards every result, so the side
 * effects are the only evidence the calls happened at all.
 *
 * `acc' starts at 7 and not at 0, which is load-bearing: with 0, put(n)
 * would return exactly n, and a compiler that used the discarded result
 * where the argument belongs would compute the right answer by luck. With 7
 * the two quantities differ at every call.
 *
 * `hook' points at put(), so the indirect call adds to the same total.
 * Same arithmetic as drivers/voidcall.c.
 */
	.text
	.globl _start
_start:
	li	a0,20
	call	emit
	la	t0,acc
	lw	a0,0(t0)
	li	a7,93
	ecall

/* put(c): acc += c; return acc. */
	.globl put
put:
	la	t0,acc
	lw	t1,0(t0)
	add	t1,t1,a0
	sw	t1,0(t0)
	mv	a0,t1
	ret

/* done(): nothing at all, which is the whole of a void call. */
	.globl done
done:
	ret

	.data
	.align	2
	.globl acc
acc:
	.word	7
	.align	2
	.globl hook
hook:
	.word	put
