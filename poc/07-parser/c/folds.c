/* Constant folding and the algebraic identities simp.c applies while building
 * the tree: the multiply by a power of two becomes a shift, the adds by zero
 * and the multiply by one disappear, and 3+4 never reaches the DAG. */
int folds(int a)
{
    int x;

    x = 3 + 4;
    x = x + 0;
    x = a * 8;
    x = a * 1;
    x = a / 1;
    x = 100 / 7;
    x = a << 0;
    x = (2 + 3) * a;
    return x;
}
