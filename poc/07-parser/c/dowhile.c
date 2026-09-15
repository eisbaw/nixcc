/* do/while: the one loop whose test is at the bottom and whose entry needs no
 * branch at all. */
int down(int n)
{
    int s;

    s = 0;
    do {
        s = s + n;
        n = n - 1;
    } while (n > 0);
    return s;
}
