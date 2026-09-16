/* Host driver for ir/lbuf.c: same argument as drivers/lbuf.s. */
#include <stdio.h>

int pack(int);

int main(void)
{
    printf("%d\n", pack(1));
    return 0;
}
