/* Host driver for ir/loop.c: same vector and length as drivers/loop.s. */
#include <stdio.h>

int sum(int *, int);

static int vec[5] = { 3, -1, 10, 7, 100 };

int main(void)
{
    printf("%d\n", sum(vec, 5));
    return 0;
}
