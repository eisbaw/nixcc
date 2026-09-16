/* A case whose point is the STDERR, not the IR.
 *
 * Criterion #7 exists because task-011's constant evaluator returns a
 * `warnings' list that nothing prints: a parser that took the value and
 * dropped the rest would compile a silently clamped constant and pass every
 * other check in this PoC. So the corpus needs forms lcc actually diagnoses,
 * and this file is them -- a shift past the width of the type, a statement
 * with no effect, a constant too large for the type it is converted to, a
 * function that falls off its end, and code after a return.
 *
 * AND THE ESCAPES IN A STRING LITERAL, which are the same argument one layer
 * down: poc/06-constants RECORDS a diagnosed escape and prints nothing, so the
 * SCON arm of the parser has to replay it or a literal whose bytes were
 * silently clamped compiles clean. `\q' is not an escape, and the other two
 * name a value that does not fit a byte. All three reach the listing with a
 * value anyway, so no other check here can see them.
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

int escapes(int i)
{
    return "a\q b"[i] + "\x1ff"[i] + "\501"[i];
}
