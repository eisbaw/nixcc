int g;
extern int h(int, int);

int f(int a, int b)
{
    int x;
    x = a + b;
    x = x - 1;
    x = x * b;
    x = x / b;
    x = x << 2;
    g = x;
    if (x > 10)
        x = h(x, g);
    return x;
}
