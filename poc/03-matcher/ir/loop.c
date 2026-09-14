int sum(int *v, int n)
{
    int i;
    int s;

    s = 0;
    i = 0;
    while (i < n) {
        s = s + v[i];
        i = i + 1;
    }
    return s;
}
