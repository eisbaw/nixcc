/* Host driver for ir/udiv.c: same arguments as drivers/udiv.s. */
#include <stdio.h>

unsigned wrap(unsigned, unsigned);

int main(void)
{
    printf("%u\n", wrap(0xfffffffeu, 0x80000001u));
    return 0;
}
