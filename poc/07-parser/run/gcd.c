/* Program two: Euclid's algorithm in a while loop, and a recursive Fibonacci,
 * so that the demonstration covers a loop carrying a remainder and a function
 * that calls itself twice in one expression. */

extern int wc(int ch);

int show(int n)
{
    if (n >= 10)
        show(n / 10);
    wc(n % 10 + 48);
    return 0;
}

int gcd(int a, int b)
{
    while (b != 0) {
        int t;
        t = b;
        b = a % b;
        a = t;
    }
    return a;
}

int fib(int n)
{
    if (n < 2)
        return n;
    return fib(n - 1) + fib(n - 2);
}

int run(int n)
{
    show(gcd(1071, 462));
    wc(32);
    show(fib(n));
    wc(10);
    return 0;
}
