/* Program four, and one of the two this slice had to leave out. It uses `&',
 * `|', `^', `~' and unary `-', all of which the parser compiled correctly and
 * diffed clean against the oracle from the day it was written -- and none of
 * which poc/03-matcher/rules.nix had a RULE for, so it was refused at
 * instruction selection and dropped from run/. task-051 added the rules.
 *
 * bitcount() is the reason `n' is kept non-negative: `>>' on a negative int is
 * an arithmetic shift, so the loop would never terminate. That is a property
 * of the C and not of the backend, and it is why the unsigned program beside
 * this one is the place a logical shift gets exercised.
 *
 * twos() is the two's-complement identity `-(~n) - 1 == n', written the long
 * way round so that BCOMI4 and NEGI4 both appear and neither can be folded
 * away; cases.nix computes the same thing from Nix's own `bitXor'.
 */

extern int wc(int ch);

int show(int n)
{
    if (n >= 10)
        show(n / 10);
    wc(n % 10 + 48);
    return 0;
}

int bitcount(int n)
{
    int c;

    c = 0;
    while (n != 0) {
        c = c + (n & 1);
        n = n >> 1;
    }
    return c;
}

int twos(int n)
{
    return -((~n) + (-n));
}

int mix(int a, int b)
{
    return (a & b) | (a ^ b);
}

int run(int n)
{
    show(bitcount(n * 7));
    wc(32);
    show(twos(n));
    wc(32);
    show(mix(n, n + 5));
    wc(10);
    return 0;
}
