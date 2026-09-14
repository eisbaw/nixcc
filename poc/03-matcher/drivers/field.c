/* Host driver for ir/field.c: same field values as drivers/field.s. */
#include <stdio.h>

struct pt { int x; int y; };

int dist(struct pt *);

int main(void)
{
    struct pt p;

    p.x = 11;
    p.y = 40;
    printf("%d\n", dist(&p));
    return 0;
}
