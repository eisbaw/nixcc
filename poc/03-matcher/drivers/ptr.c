/* Host driver for ir/ptr.c: same tag[] bytes, the same take() and the same
 * argument as drivers/ptr.s. `walk(2)' is called into a variable rather than
 * inlined into the printf, because `hold + *walk(2)' does not say which of
 * the two happens first. */
#include <stdio.h>

char tag[8] = { 1, 2, 4, 8, 16, 32, 64, 100 };
int hold = 0;

int take(char *s, int n)
{
    return s[0] * 10 + n;
}

char *walk(int);

int main(void)
{
    char *r = walk(2);
    printf("%d\n", hold + *r);
    return 0;
}
