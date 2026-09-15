/* Host driver for ir/gsym.c: same table values as drivers/gsym.s. */
#include <stdio.h>

int tbl[4] = { 4, 0, 100, 0 };

int pick(int);

int main(void)
{
    printf("%d\n", pick(20));
    return 0;
}
