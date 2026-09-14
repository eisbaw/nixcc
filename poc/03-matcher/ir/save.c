/* Holds MORE common-subexpression registers before a mid-forest label than
 * after it. That is the shape that catches a mistake the earlier version of
 * this emitter made: the prologue decided which callee-saved registers to save
 * from the allocation cursor, which resets at a label, instead of from a
 * running maximum. This function wrote s10, held it across a call to
 * __mulsi3, and neither saved nor restored it -- correct-looking assembly that
 * corrupts its caller's register.
 *
 * check.nix's saved-register cross-check reads the EMITTED prologue, so it
 * catches that. It only reaches it on a function shaped like this one.
 */
int hold(int a, int b)
{
    int r;

    r = a + (a ? b * b : a);
    return r;
}
