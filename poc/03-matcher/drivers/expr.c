/* Host driver for ir/expr.c: same call, same arguments as drivers/expr.s. */
#include <stdio.h>

int f(int, int);

int h(int a, int b) { return a + b; }

int main(void)
{
    printf("%d\n", f(7, 3));
    return 0;
}
