/* A program that needs the preprocessor to compile at all, and whose ANSWER
   depends on which arm of each conditional was taken.
 *
 * Every constant below is chosen so a wrong choice is visible in the output
 * rather than cancelling out: BIAS is 7 or 1000, EXTRA is 2 or 500. That is
 * ir/unsig.c's lesson -- its divisor of 7 gave the same number whether the
 * signed or the unsigned divide ran -- applied to a conditional.
 */
#define BASE  10
#define SCALE 3

#if BASE > 8
#define BIAS 7
#else
#define BIAS 1000
#endif

#ifdef NDEBUG
#define EXTRA 500
#else
#define EXTRA 2
#endif

extern int wc(int ch);          /* writes one character to stdout */

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

    acc = BIAS;
    for (i = 1; i <= n; i++)
        acc = acc + i * SCALE + EXTRA;

    show(acc);
    wc(10);
    return 0;
}
