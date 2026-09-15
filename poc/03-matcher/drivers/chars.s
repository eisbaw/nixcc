/* Calls scan(4) and exits with the result. Same data as drivers/chars.c.
 *
 * sbuf and ubuf hold the SAME four bytes and shalf and uhalf the same
 * halfword, and 0xf0 and 0x80 have their high bit set. What that makes
 * visible is the CONVERSION the rule table chooses -- an arithmetic shift
 * against a mask -- and not the load: lcc promotes every narrow load, and the
 * conversion re-normalises the register, so lb and lbu leave the same bits
 * behind. See ir/chars.c's header and cases.nix's `narrowLoads'.
 */
	.text
	.globl _start
_start:
	li	a0,4
	call	scan
	li	a7,93
	ecall

	.data
	.align	2
	.globl sbuf
sbuf:
	.byte	0xf0, 0x01, 0x7f, 0x80
	.align	2
	.globl ubuf
ubuf:
	.byte	0xf0, 0x01, 0x7f, 0x80
	.align	2
	.globl shalf
shalf:
	.half	0x8001, 0
	.align	2
	.globl uhalf
uhalf:
	.half	0x8001, 0
