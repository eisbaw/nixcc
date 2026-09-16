/* The POINTER opcodes (task-054): CNSTP4, CVUP4, CVPU4, SUBP4 and RETP4, which
 * poc/07-parser emits for ordinary C and poc/03-matcher/rules.nix had a row
 * for none of. `p == 0' is not an exotic form -- it is how every C program
 * written before nullptr tests a pointer -- and it compiled to IR that diffed
 * clean against lcc and was then refused at instruction selection.
 *
 * WHERE EACH OPCODE COMES FROM, because most of them are not written in the C:
 *
 *   CNSTP4   twice, and the two are different rules. `z = 0' is the null
 *            pointer constant, which lcc prints as `0' and `reg_zerop'
 *            takes into the zero register. `z = (char *) 100000' is a NON-null
 *            pointer constant, which lcc prints as `0x186a0' -- sym.c asks for
 *            `%p' and lcc's own vfprint, in output.c, writes the `0x' only
 *            when the pointer is not null -- so
 *            `emit.nix''s decimal-only `constValue' returns null for it, the
 *            range predicate cannot match, and it goes through
 *            `reg_cnstp_wide' and reaches poc/04-assembler as hex. That is
 *            the same path ir/unsig.c's 0xdeadbeef takes for CNSTU4.
 *   CVPU4    every pointer COMPARISON is one: `p == 0' is not a pointer
 *            operation in the IR at all, it is CVPU4 on the pointer and an
 *            unsigned compare against CNSTU4 0. So is the left half of a
 *            pointer difference.
 *   CVUP4    `(char *) (u + 1000)': unsigned arithmetic cast back to a
 *            pointer, WRITTEN TWICE, and the repetition is the test rather
 *            than a slip. The rule emits `mv %c,%0', and a one-kid node is
 *            reduced at the same depth as its kid, so with a single use the
 *            destination and the source are the SAME register and the whole
 *            instruction is a self-move -- measured: with one use, replacing
 *            the template with `mv %c,%c' left ptr.s byte-identical and the
 *            row was pinned by nothing but its mnemonic. Two uses make lcc
 *            share the node, the matcher HOLDS it in a common-subexpression
 *            register, and the move finally has a destination different from
 *            its source. The offset is 1000 and not 4 for the same reason:
 *            the value this rule carries has to be one a stale register is
 *            unlikely to be holding already.
 *
 *            NEVER DEREFERENCED, and that is a constraint rather than a
 *            choice -- see the host-oracle paragraph below.
 *   SUBP4    `p - n': pointer minus INTEGER, which is not the SUBU4 a
 *            pointer difference lowers to.
 *   RETP4    the function returns a pointer. Nothing under poc/07-parser/run/
 *            can exercise this one, because calling a pointer-returning
 *            function is CALLP4 and rules.nix deliberately has no row for it
 *            (task-036, and task-057 is where that row goes); the caller here
 *            is drivers/ptr.s, which is assembly, so it can.
 *   ARGP4    `take(q, n)' passes a pointer. The row has existed since
 *            task-025 and no corpus case had ever selected it (task-053).
 *
 * WHAT MAKES THE ANSWER MOVE, which is the part a file of pointer expressions
 * does not get for free:
 *
 *   * THE THREE TESTS DISAGREE. `z == 0' is true, `p == 0' is false and
 *     `q != 0' is true, and they add 1000, 2000 and 300. A null comparison
 *     that is always false -- or always true -- discriminates nothing, which
 *     is why all three are here and why the amounts differ.
 *   * `tag' HOLDS EIGHT DIFFERENT VALUES, spaced 1, 2, 4, 8, 16, 32, 64, 100,
 *     so a pointer off by one element changes the byte it reads rather than
 *     reading the same thing twice. `*q' and `take(q, n)' both read through
 *     the pointer SUBP4 produced, so both move if that subtraction is wrong.
 *   * `p - q' IS NOT ZERO. It is n, and n is 2: a pointer difference of zero
 *     is the pointer version of ir/unsig.c's divisor of 7, right whatever the
 *     subtraction did.
 *   * THE TWO ANSWERS ARE INDEPENDENT. `hold' carries the whole integer
 *     computation and the RETURNED POINTER carries only `n + 4', so a defect
 *     in the arithmetic cannot cancel against a defect in the return. The
 *     driver adds the two, and drivers/ptr.c does the same on the host.
 *
 * WHY THE CVUP4 POINTER IS NEVER DEREFERENCED, which is the one place the
 * ORACLE constrains the C rather than the target. drivers/ptr.c is compiled by
 * the host compiler as an independent answer to the same question, and the
 * host is 64-bit: `(unsigned) p' there truncates a pointer to 32 bits and
 * casting the result back produces an address that is not the one it came
 * from. Measured, not guessed -- the first version of this file did exactly
 * that and segfaulted the host oracle. So `u' is a pointer DIFFERENCE, which
 * is a small number on any target, and the pointer built back out of it is
 * only ever read as an integer.
 */
extern char tag[8];
extern int hold;
extern int take(char *s, int n);

char *walk(int n)
{
    char *p;
    char *q;
    char *z;
    unsigned u;
    int r;

    p = tag + 3;
    q = p - n;
    z = 0;

    r = n;
    if (z == 0)
        r = r + 1000;
    if (p == 0)
        r = r + 2000;
    if (q != 0)
        r = r + 300;

    u = (unsigned) (p - tag);
    z = (char *) (u + 1000);
    r = r + (int) z + (int) (char *) (u + 1000);

    r = r + (int) (p - q);
    r = r + *q;
    r = r + take(q, n);

    z = (char *) 100000;
    r = r + (int) z;

    hold = r;
    return tag + n + 4;
}
