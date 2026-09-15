/* Host driver for ir/voidcall.c: same arithmetic as drivers/voidcall.s.
 * `acc' starts at 7 for the reason that file gives. */
#include <stdio.h>

static int acc = 7;

int put(int c)
{
    acc += c;
    return acc;
}

void done(void)
{
}

int (*hook)(int) = put;

int emit(int);

int main(void)
{
    emit(20);
    printf("%d\n", acc);
    return 0;
}
