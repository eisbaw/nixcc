/* `long' is four bytes here, so it shares every opcode with `int' and differs
 * only in the type= fields of the listing. That is exactly the case
 * poc/06-constants/oracle.nix warned is invisible in the IR, so it is worth a
 * corpus entry: a diff that only reads node lines would pass this on a bug. */
long widen(long a, int b)
{
    long x;

    x = a + b;
    x = x * 3;
    return x;
}
