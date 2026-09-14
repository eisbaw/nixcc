/* Host driver for ir/argcall.c: same argument as drivers/argcall.s. */
#include <stdio.h>

int nested(int);

int h(int a, int b) { return a + b; }

int main(void)
{
    printf("%d\n", nested(6));
    return 0;
}
