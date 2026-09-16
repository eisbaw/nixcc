/* Program three: nested loops and a remainder test, plus a shift used as a
 * multiply, so the demonstration covers a loop inside a loop and the
 * libcall-shaped operators.
 *
 * There is no `&', `|', `^', `~' or unary `-' in here and no `unsigned'
 * arithmetic, and that is now a property of this program rather than of the
 * backend. When it was written poc/03-matcher/rules.nix had no RULE for
 * those opcodes, so a program using them was refused at instruction
 * selection rather than miscompiled -- the right failure, and still the
 * reason run/ held three programs instead of five. task-051 added the rules;
 * run/bits.c and run/unsig.c are what exercises them.
 */

extern int wc(int ch);

int show(int n)
{
    if (n >= 10)
        show(n / 10);
    wc(n % 10 + 48);
    return 0;
}

int isprime(int n)
{
    int d;

    if (n < 2)
        return 0;
    d = 2;
    while (d * d <= n) {
        if (n % d == 0)
            return 0;
        d = d + 1;
    }
    return 1;
}

int countprimes(int n)
{
    int i;
    int c;

    c = 0;
    for (i = 0; i < n; i++)
        if (isprime(i))
            c = c + 1;
    return c;
}

int run(int n)
{
    show(countprimes(n << 3));
    wc(32);
    show(countprimes(n) * 100 / 7);
    wc(10);
    return 0;
}
