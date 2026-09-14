/* Host driver for ir/cond.c: same arguments as drivers/cond.s. */
#include <stdio.h>

int probe(int, int);

int main(void)
{
    printf("%d\n", probe(5, 9));
    return 0;
}
