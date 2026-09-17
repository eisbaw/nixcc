#define LIMIT      6            /* object-like macros and #if */
#define VERBOSE    1
#define TERM(i, k) ((i) * (k))  /* a function-like macro, with parameters */
#define NAME(n)    total ## n   /* ## pastes a new identifier out of two */

extern int wc(int ch);

int show(int v) { if (v >= 10) show(v / 10); wc(v % 10 + 48); return 0; }

int run(int n)
{
#if VERBOSE && LIMIT > 3
    int NAME(1);
    int i;

    NAME(1) = 0;
    for (i = 1; i <= LIMIT; i++)
        NAME(1) = NAME(1) + TERM(i, n);
    show(NAME(1));
#else
    show(0);
#endif
    wc(10);
    return 0;
}
