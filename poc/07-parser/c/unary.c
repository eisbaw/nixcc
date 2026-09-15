/* The unary operators, including the two that lcc rewrites rather than
 * emitting: `!e' becomes a comparison against zero, and unary `+' is a no-op
 * that still promotes. */
int unary(int a)
{
    int x;

    x = -a;
    x = ~x;
    x = +x;
    x = !x;
    return x;
}
