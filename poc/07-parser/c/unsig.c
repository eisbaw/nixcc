/* Unsigned arithmetic, where the operand type decides the opcode letter, and
 * the two unsigned comparisons simp.c answers without looking at the operand.
 * `u >= 0' is always true and lcc SAYS SO -- that warning is part of the
 * stderr this slice's oracle compares. */
unsigned ufun(unsigned a, unsigned b)
{
    unsigned x;

    x = a + b;
    x = x / b;
    x = x % b;
    x = x >> 2;
    if (a >= 0) x = x + 1;
    if (a < b) x = x + 2;
    if (a >= b) x = x + 3;
    return x;
}

/* The two conversions between the signed and unsigned four-byte types. They
 * are invisible in a listing that only reads opcodes and widths -- CVUI4 and
 * CVIU4 are both four to four -- which is why they get a case of their own. */
int narrow(unsigned u)
{
    return u / 2;
}

unsigned widen(int a)
{
    unsigned u;

    u = a;
    return u;
}
