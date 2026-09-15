/* `const' and `volatile', which look like decoration and are not.
 *
 * A const local with an initialiser only compiles because enode.c's asgn()
 * temporarily strips the qualifier off the symbol's type around the
 * assignment -- asgntree() refuses an assignment to a const identifier, and an
 * initialiser goes through asgntree. Nothing else in the corpus reaches that
 * path, and the frontend refused this file until the strip was ported.
 *
 * A volatile load is built with newnode rather than node, so two reads of the
 * same volatile object are two dag nodes where two reads of an ordinary one
 * would be `count=2' on one node. That is visible in the listing and in
 * nothing else.
 */
int quals(int a)
{
    const int c = 7;
    volatile int v;
    int x;

    v = a;
    x = v + v;
    return x + c;
}
