/* A conditional expression used for its value, and one nested inside another,
 * which is what makes dag.c's COND arm equate labels rather than jump. */
int pick(int a, int b)
{
    int r;

    r = a > b ? a : b;
    r = r + (a ? (b ? 1 : 2) : 3);
    return r;
}
