#define LIMIT   6            /* object-like macros and #if are slice 1 */
#define VERBOSE 1

extern int wc(int ch);

int show(int v) { if (v >= 10) show(v / 10); wc(v % 10 + 48); return 0; }

int run(int n)
{
#if VERBOSE && LIMIT > 3
    int total;
    int i;

    total = 0;
    for (i = 1; i <= LIMIT; i++)
        total = total + i * n;
    show(total);
#else
    show(0);
#endif
    wc(10);
    return 0;
}
