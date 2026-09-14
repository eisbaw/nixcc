/* Host driver for ir/save.c: same arguments as drivers/save.s. */
#include <stdio.h>

int hold(int, int);

int main(void)
{
    printf("%d\n", hold(6, 7));
    return 0;
}
