/* Host driver for ir/bits.c: same arguments as drivers/bits.s. */
#include <stdio.h>

int mask(int, int);

int main(void)
{
    printf("%d\n", mask(-1234, 5678));
    return 0;
}
