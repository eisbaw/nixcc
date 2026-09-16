/* Criterion #3 of task-054: a C program that COMPARES A POINTER AGAINST ZERO,
 * compiled from this .c and run on the emulator inside one `nix eval'.
 *
 * `p == 0' is not an exotic form -- it is how every C program written before
 * nullptr tests a pointer -- and until task-054 it compiled to IR that diffed
 * clean against lcc and was then refused at instruction selection, loudly and
 * by name. No program under run/ reached it, which is why nothing noticed.
 *
 * WHAT IS ACTUALLY BEING TESTED, because `p == 0' is not one opcode. lcc does
 * not compare pointers: it converts the pointer to an unsigned (CVPU4) and
 * compares THAT against CNSTU4 0, so the null test needs the conversion rule
 * and the null pointer constant CNSTP4 needs its own. The rest of the file
 * reaches the other pointer rows the same way:
 *
 *   the search       `z = 0' then `z = buf + i' -- a null pointer constant
 *                    that means "not found", tested BOTH WAYS. One search
 *                    finds its character and one does not, so the branch is
 *                    taken once and not taken once; a null test that always
 *                    answers the same way discriminates nothing.
 *   `p - buf'        a pointer DIFFERENCE, which is two CVPU4 and an unsigned
 *                    subtract, and the difference is 6 and not 0 -- a
 *                    difference of zero is right whatever the subtraction did.
 *   `p - len'        a pointer minus an INTEGER, which is SUBP4 and a
 *                    different opcode from the above. The byte it lands on is
 *                    printed, so landing one element out changes the output.
 *   `(char *) (u+n)' an unsigned cast back to a pointer, CVUP4. It is never
 *                    dereferenced, and that is deliberate: the expected output
 *                    is computed by a second implementation in Nix, and a
 *                    pointer built out of arithmetic has no value that program
 *                    could know.
 *
 * RETP4 -- a function that RETURNS a pointer -- is not here and cannot be:
 * calling one is CALLP4, which poc/03-matcher/rules.nix deliberately has no
 * row for, so only a hand-written assembly caller can reach a pointer-returning
 * function. poc/03-matcher/ir/ptr.c is that case, and it is executed on the
 * same emulator.
 *
 * THE ARGUMENT IS PART OF THE TEST. `n' picks where the alphabet starts, so it
 * decides which character the search finds and at which index, and it appears
 * again in the CVUP4 arithmetic. A program whose output did not depend on it
 * could not tell a compiler that ran it from one that ignored it.
 */
extern int wr(int fd, char *buf, int n);

int run(int n)
{
    char buf[16];
    char *p;
    char *z;
    unsigned u;
    int len;
    int i;
    int hit;
    int miss;

    i = 0;
    while (i < 6) {
        buf[i] = 'a' + (n + i) % 5;
        i = i + 1;
    }
    buf[6] = 0;

    /* strlen, by walking a pointer to the terminator and subtracting. */
    p = buf;
    while (*p != 0)
        p = p + 1;
    len = (int) (p - buf);

    /* A search that FINDS its character... */
    z = 0;
    i = 0;
    while (i < len) {
        if (buf[i] == 'c') {
            z = buf + i;
            i = len;
        }
        i = i + 1;
    }
    if (z == 0)
        hit = 9;
    else
        hit = (int) (z - buf);

    /* ...and one that does not, so both arms of the null test run. */
    z = 0;
    i = 0;
    while (i < len) {
        if (buf[i] == 'z') {
            z = buf + i;
            i = len;
        }
        i = i + 1;
    }
    if (z == 0)
        miss = 1;
    else
        miss = 0;

    u = (unsigned) (p - buf);
    z = (char *) (u + n);
    p = p - len;

    buf[len] = '0' + hit;
    buf[len + 1] = '0' + miss;
    buf[len + 2] = '0' + (int) z % 10;
    buf[len + 3] = *p;
    buf[len + 4] = '\n';
    wr(1, buf, len + 5);
    return 0;
}
