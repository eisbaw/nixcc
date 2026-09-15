/* Prefix and postfix ++/--. The postfix forms build the RIGHT(RIGHT(p,asgn),p)
 * shape that tree.c's root1 de-constructs when the value is discarded, so the
 * discarded and used cases produce different trees from the same source. */
int incr(int a)
{
    int i;
    int j;

    i = a;
    i++;
    --i;
    j = i++;
    j = j + --i;
    return j;
}
