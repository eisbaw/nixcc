/* Compiled and run entirely by Nix:  just run example.c 7  */

extern int wc(int ch);          /* writes one character to stdout */

struct acc { int sum; int n; };

int show(int v)
{
    if (v >= 10) show(v / 10);
    wc(v % 10 + 48);
    return 0;
}

int run(int n)
{
    struct acc a;
    int i;

    a.sum = 0;
    a.n = n;
    for (i = 1; i <= a.n; i++)
        a.sum = a.sum + i * i;

    show(a.sum);                /* sum of squares 1..n */
    wc(10);
    return 0;
}
