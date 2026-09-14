/* A conditional expression puts LABELS INSIDE a forest -- lcc does that in 56
 * of the 4800 forests in its own tst/ corpus -- and here the load of `a' is a
 * node lcc shares across one: `2. INDIRI4 count=2' is read by the test before
 * the branch and by the addition after the join.
 *
 * That is the case that says whether a value may be held in a register across
 * a branch target. It may not: this emitter has no control-flow analysis, so
 * it cannot know that every path reaching the label filled the register. The
 * expected code therefore RELOADS `a' after the label rather than reusing it.
 */
int probe(int a, int b)
{
    int r;

    r = a + (a ? b : a);
    return r;
}
