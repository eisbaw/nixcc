/* Host driver for ir/mod.c: same arguments as drivers/mod.s. */
#include <stdio.h>

int rem(int, int);

int main(void)
{
    printf("%d\n", rem(-7, 3));
    return 0;
}
