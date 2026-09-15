/* Nested blocks with shadowing, and an explicit `register' declaration -- which
 * checkref() reads as "this function has registers already", so no PARAMETER
 * gets promoted in it however often it is used. */
int scopes(int a)
{
    register int r;
    int x;

    r = a;
    {
        int x;
        x = r + 1;
        r = x;
    }
    x = r + a + a + a;
    return x;
}
