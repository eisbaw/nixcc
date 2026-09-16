/* Criteria #3 to #6 of task-058, in one program: struct, union and enum
 * compiled from this .c and RUN on the emulator inside one `nix eval'.
 *
 * WHAT MAKES THE NUMBER DISCRIMINATING, because a record program is easy to
 * write so that nothing it prints depends on the layout. The members are read
 * back TWICE, and the two reads fail in different ways:
 *
 *   the weighted read   `p->c * 1 + p->i * 2 + p->h * 4 + p->d * 8', so a
 *                       dropped or swapped member changes the total. Weights
 *                       of 1/1/1/1 would not, and neither would four members
 *                       holding the same value: ir/unsig.c's divisor of 7 and
 *                       ir/udiv.c's cancelling halves are what that lesson has
 *                       already cost this project twice.
 *   the byte sum        the SAME storage, read one byte at a time through the
 *                       union and weighted by POSITION. This is the one that
 *                       moves when a member lands at the wrong offset even
 *                       though every value is right -- which the weighted read
 *                       above cannot see, because a member at a wrong offset
 *                       is written and read back through the same wrong
 *                       offset and agrees with itself.
 *
 * `char c' before `int i' is what puts three bytes of padding in the middle,
 * and the union is what makes the padding visible: b[1], b[2] and b[3] stay
 * zero and b[4] holds `i'. A layout that ignored alignment would put `i' at
 * offset 1 and the byte sum would move with it.
 *
 * THE SIZES ARE CHECKED AGAINST THE EXECUTED VALUE and not only against the IR
 * diff. `sizeof(struct R)' is 12 because 11 rounds up to the aggregate's own
 * alignment; a frontend that skipped that round-up would print 11 here while
 * its listing still diffed clean against lcc on every other line.
 *
 * THE ENUM IS NOT DECORATION. `W2' has no explicit value and is 2 because the
 * implicit counter resumes from `W1 = 1'. An enumerator numbered from its
 * position would make it 1, and the weighted read would come out short by the
 * whole of `i'.
 *
 * A LOCAL STRUCT AND A STRUCT THROUGH A POINTER ARE BOTH HERE, which is what
 * criterion #3 asks for. `d' is a local struct, written and read with `.'
 * alone; `p' reaches the same members with `->', through a union. The values
 * travel from one to the other, so a local struct laid out differently from
 * the one behind the pointer changes what is stored.
 *
 * `n' IS PART OF THE TEST: two members are written as offsets from the
 * argument, so a compiler that ignored it could not print this. cases.nix
 * holds the range `n' must stay in for the byte-by-byte read to describe what
 * is printed, as a guard rather than as a comment.
 *
 * NO STRUCT-TO-STRUCT COPY, deliberately. That is ASGNB, and the rule table
 * has no row for it until task-060; c/structs.c is where the copy is diffed
 * against lcc instead.
 */
extern int wc(int ch);

struct R {
    char  c;
    int   i;
    short h;
    char  d;
};

union V {
    struct R r;
    char     b[16];
};

enum W { W1 = 1, W2, W4 = 4, W8 = 8 };

int show(int v)
{
    if (v >= 10)
        show(v / 10);
    wc(v % 10 + 48);
    return 0;
}

int weigh(struct R *p)
{
    return p->c * W1 + p->i * W2 + p->h * W4 + p->d * W8;
}

int run(int n)
{
    union V v;
    struct R d;
    struct R *p;
    int i;
    int pos;

    p = &v.r;
    for (i = 0; i < 16; i++)
        v.b[i] = 0;

    d.c = 3;
    d.i = n - 5;
    d.h = n - 3;
    d.d = 9;

    p->c = d.c;
    p->i = d.i;
    p->h = d.h;
    p->d = d.d;

    pos = 0;
    for (i = 0; i < 16; i++)
        pos = pos + v.b[i] * (i + 1);

    show(sizeof(struct R));
    wc(32);
    show(sizeof(union V));
    wc(32);
    show(sizeof(enum W));
    wc(32);
    show(weigh(p));
    wc(32);
    show(pos);
    wc(10);
    return 0;
}
