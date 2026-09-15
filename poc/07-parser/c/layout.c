/* The frame layout, which is decided by REFERENCE COUNT and not by declaration
 * order: decl.c sorts a block's locals descending by `ref' before symbolic.c
 * assigns offsets, and `ref' is weighted by loop depth (refinc is multiplied by
 * ten inside a loop). So `hot' below, declared second and read inside the
 * loop, lands at offset 0 and `rare' at 4.
 *
 * Nothing else in the corpus distinguishes the sorted order from the
 * declaration order, which means without this file a frontend that dropped the
 * sort entirely would still diff clean.
 */
int layout(int n)
{
    int rare;
    int hot;

    rare = n;
    hot = 0;
    while (hot < n)
        hot = hot + rare;
    return hot;
}
