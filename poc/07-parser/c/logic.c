/* Short-circuit && and ||, and a `!' over a comparison. These are the cases
 * where dag.c's AND/OR arms allocate their own labels mid-forest. */
int logic(int a, int b)
{
    int n;

    n = 0;
    if (a > 0 && b > 0) n = 1;
    if (a < 0 || b < 0) n = n + 2;
    if (!(a == b)) n = n + 4;
    return n;
}
