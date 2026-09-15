/* All six comparisons in a condition, where lcc INVERTS them: a false-label
 * branch emits the opposite opcode, so `<' here must come out as GEI4. */
int cmp(int a, int b)
{
    int n;

    n = 0;
    if (a < b) n = n + 1;
    if (a > b) n = n + 2;
    if (a <= b) n = n + 3;
    if (a >= b) n = n + 4;
    if (a == b) n = n + 5;
    if (a != b) n = n + 6;
    return n;
}
