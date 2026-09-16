/* Program five, and the other one this slice had to leave out: `unsigned'
 * arithmetic, for which poc/03-matcher/rules.nix had no rule of any kind until
 * task-051 -- not the arithmetic, not the comparisons, not the calls.
 *
 * EVERY VALUE HERE IS ABOVE 2^31, which is the whole point. Read as signed
 * integers these are negative, and the signed rules would answer differently:
 * u / 3 and u % 7 go through __udivsi3 and __umodsi3 rather than the signed
 * pair, `u >> 5' is a LOGICAL shift that brings zeros down from the top rather
 * than ones, and `n >= 10u' in ushow() is an unsigned comparison. A program
 * whose unsigned data stayed small would compile to the same IR and prove none
 * of that.
 *
 * 0xffffff00u is also the one constant in run/ wide enough that lcc spells it
 * in HEXADECIMAL -- sym.c switches at 32768 -- so this program is what takes
 * `0x...' through the frontend's own vtoa, the rule table's wide-constant row
 * and poc/04-assembler's integer parser in a single evaluation.
 *
 * ushow() takes `unsigned' rather than `int' so that the division that prints
 * each digit is the unsigned one; `n % 10u + 48' is unsigned and becomes an
 * `int' again through the conversion lcc inserts at wc()'s prototype.
 */

extern int wc(int ch);

int ushow(unsigned n)
{
    if (n >= 10u)
        ushow(n / 10u);
    wc(n % 10u + 48);
    return 0;
}

unsigned hashmix(unsigned x)
{
    x = x ^ (x >> 5);
    x = x & 0xffffu;
    return x;
}

int run(int n)
{
    unsigned u;

    u = 0xffffff00u + n;
    ushow(u / 3u);
    wc(32);
    ushow(u % 7u);
    wc(32);
    ushow(hashmix(u));
    wc(10);
    return 0;
}
