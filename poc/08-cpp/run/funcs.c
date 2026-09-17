/* A program that needs slice 2 to compile at all, and whose ANSWER depends on
 * each of the three things slice 2 added.
 *
 * Every constant is chosen so a wrong choice is visible in the number rather
 * than cancelling out -- ir/unsig.c's lesson, whose divisor of 7 gave the same
 * answer whether the signed or the unsigned divide ran:
 *
 *   BLEND(a, b)   is `((a) * 4 + (b))', which is NOT symmetric, so a
 *                 substitution that put the arguments in each other's places
 *                 changes the total.  A body of `a * b' would not have
 *                 noticed.  It is invoked with a MULTI-TOKEN argument,
 *                 `v + 1', so the parentheses in the body are load-bearing:
 *                 drop them and `(v + 1) * 4 + 2' becomes `v + 1 * 4 + 2'.
 *   PICK(n)       pastes `step ## n' into a function name, and step1 and
 *                 step2 blend with different arguments, so a paste that built
 *                 the wrong name -- or was not rescanned as a name at all --
 *                 calls a function that gives a different sum.
 *   TAG(x)        stringifies a TWO-TOKEN argument written with two spaces in
 *                 it.  Byte 0 is `K' (75) and byte 2 is `J' (74) only if the
 *                 internal whitespace was collapsed to ONE space; without the
 *                 collapse byte 2 is a space (32) and the answer moves.  An
 *                 earlier version passed a single identifier and read one
 *                 byte, which tested nothing about `#' except that it emitted
 *                 something beginning with K.
 */

extern int wc(int ch);          /* writes one character to stdout */

#define BLEND(a, b)     ((a) * 4 + (b))
#define BIAS(v)         ((v) + 5)
#define PICK(n)         step ## n
#define TAG(x)          #x

int step1(int v)
{
    return BLEND(v + 1, 1);
}

int step2(int v)
{
    return BLEND(v + 1, 2);
}

int show(int v)
{
    if (v >= 10) show(v / 10);
    wc(v % 10 + 48);
    return 0;
}

int run(int n)
{
    int i;
    int acc;
    char *tag;

    tag = TAG(K  J);
    acc = 0;
    for (i = 1; i <= n; i++)
        acc = acc + PICK(2)(i);

    show(BIAS(acc) + tag[0] + tag[2]);
    wc(10);
    return 0;
}
