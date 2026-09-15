/* A case whose point is the STDERR, not the IR.
 *
 * Criterion #7 exists because task-011's constant evaluator returns a
 * `warnings' list that nothing prints: a parser that took the value and
 * dropped the rest would compile a silently clamped constant and pass every
 * other check in this PoC. So the corpus needs forms lcc actually diagnoses,
 * and this file is them -- a shift past the width of the type, a statement
 * with no effect, a constant too large for the type it is converted to, a
 * function that falls off its end, and code after a return.
 */
int warns(int a)
{
    int x;

    x = a << 40;
    a + 1;
    x = x + 99999999999999999999;
    return x;
}

int falls(int a)
{
    a = a + 1;
}

int unreachable(int a)
{
    return a;
    a = 2;
}
