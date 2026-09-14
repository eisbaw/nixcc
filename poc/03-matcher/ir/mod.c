/* `%` is the third RV32I libcall (decision-003) and the only one whose sign
 * rule is easy to get wrong: C truncates toward zero, so -7 % 3 is -1 and not
 * 2. The branch is deliberately taken only on a negative remainder, so a
 * __modsi3 that floored instead of truncating returns a different number
 * rather than the same one by luck. */
int rem(int a, int n)
{
    int r;

    r = a % n;
    if (r < 0)
        r = r - 1;
    return r;
}
