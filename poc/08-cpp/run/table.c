/* #elif, #undef and a redefinition, in a program whose output says which
   arm ran. LEVEL picks one of four multipliers and nothing else changes, so
   an #elif chain that fell through to the #else prints a different number.
 */
#define LEVEL 3

#if LEVEL == 1
#define MULT 2
#elif LEVEL == 2
#define MULT 5
#elif LEVEL == 3
#define MULT 11
#elif LEVEL == 4
#define MULT 17
#else
#define MULT 1000
#endif

/* Defined, used, taken away and defined again with a different body: an
   #undef that quietly did nothing would leave OFFSET at 4 and change the
   answer by n. */
#define OFFSET 4
#undef OFFSET
#define OFFSET 100

extern int wc(int ch);

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

    acc = 0;
    for (i = 1; i <= n; i++)
        acc = acc + i * MULT;

    show(acc + OFFSET);
    wc(10);
    return 0;
}
