extern int h(int, int);

int nested(int a)
{
    return h(a * a, 1);
}
