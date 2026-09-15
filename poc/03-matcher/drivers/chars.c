/* Host driver for ir/chars.c: same data as drivers/chars.s. */
#include <stdio.h>

signed char sbuf[4] = { (signed char) 0xf0, 0x01, 0x7f, (signed char) 0x80 };
unsigned char ubuf[4] = { 0xf0, 0x01, 0x7f, 0x80 };
short shalf[2] = { (short) 0x8001, 0 };
unsigned short uhalf[2] = { 0x8001, 0 };

int scan(int);

int main(void)
{
    printf("%d\n", scan(4));
    return 0;
}
