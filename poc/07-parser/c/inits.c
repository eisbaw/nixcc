/* Local initialisers, which lcc compiles as assignments and then RESETS the
 * variable's reference count to one -- so `n' below is not promoted to a
 * register even though it is read three times. */
int inits(int a)
{
    int n = a;
    int m = 2;

    n = n + m;
    n = n + m;
    return n;
}
