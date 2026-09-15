/* Symbol expressions: a base symbol with a constant displacement.
 *
 * lcc folds `msg[2]' on an `int msg[]' into a single node `ADDRGP4 msg+8'
 * (task-023), so a code generator hands this assembler `la a0,msg+8' and not
 * an `la' followed by an `addi'. GNU as accepts the same spelling everywhere
 * a plain symbol goes, which is why this file can be differentially tested:
 * every displacement below is resolved from the symbol table at layout time
 * by both assemblers, and the bytes have to agree.
 *
 * Every form is here because each takes a different path through asm.nix:
 * `la' and `call' go through `pcrel', `j' through `jumpOff', `beq' through
 * `branchOff', and `.word' through the data path -- four callers of one
 * `lookup'. The negative displacement is here because the sign is the half a
 * regex can get wrong while `+' still works.
 *
 * It is assembled and compared, never executed: `call after' returns to the
 * `j' that follows it, which would loop.
 */
	.text
	.globl _start
_start:
	la	a0,tbl+8		/* the third word of tbl */
	la	a1,tbl			/* and its base, so a wrong displacement shows */
	la	a2,tbl-4		/* backwards, one word before it */
	lw	a3,0(a0)
	beq	a0,a1,after+4		/* a branch target with a displacement */
	call	after+0			/* +0 is still an expression, and must resolve */
after:
	nop
	j	done-4
	nop
done:
	ret

	.align	2
tbl:
	.word	1,2,3,4
	.word	tbl+8			/* a symbol expression as datum */
	.word	tbl-4
	.word	after+8
