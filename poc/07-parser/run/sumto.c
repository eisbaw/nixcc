/* Program one of three, and the point of the whole slice: this file is
 * compiled from C by Nix, not by lcc.
 *
 * Everything in it is inside slice 1 -- int locals and parameters, a for
 * loop, a recursive call, division and remainder, a comparison. There is no
 * array, no pointer, no global and no `char', because those are slices 2 and
 * 3 (task-028, task-029), and printing is therefore done one character at a
 * time through wc(), which the driver supplies as three instructions of
 * assembly. The syscall ABI is target knowledge; that part has never been C.
 */

extern int wc(int ch);

int show(int n)
{
    if (n >= 10)
        show(n / 10);
    wc(n % 10 + 48);
    return 0;
}

int sumto(int n)
{
    int i;
    int s;

    s = 0;
    for (i = 1; i <= n; i++)
        s = s + i;
    return s;
}

int run(int n)
{
    show(sumto(n));
    wc(10);
    return 0;
}
