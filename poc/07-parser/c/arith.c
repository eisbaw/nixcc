/* Every integer binary operator the slice covers, on int parameters, so that
 * each one reaches the DAG as its own opcode rather than being folded away. */
int arith(int a, int b)
{
    int x;

    x = a + b;
    x = x - a;
    x = x * b;
    x = x / b;
    x = x % b;
    x = x << a;
    x = x >> a;
    x = x & b;
    x = x | b;
    x = x ^ b;
    return x;
}
