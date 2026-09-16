/* Host driver for ir/unsig.c: same arguments and the same uh()/uhook as
 * drivers/unsig.s. They must agree, because the point of building this one
 * with the host compiler is that two compilers answer the same question. */
#include <stdio.h>

unsigned wide(unsigned, unsigned);

unsigned uh(unsigned a, unsigned b)
{
    return a + b;
}

unsigned (*uhook)(unsigned, unsigned) = uh;

int main(void)
{
    printf("%u\n", wide(0xfffffff0u, 9u));
    return 0;
}
