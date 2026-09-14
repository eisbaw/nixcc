/* The one argument shape this PoC refuses, and the smallest one: the libcall
 * for `a * a' runs AFTER the constant 1 has already been placed in a0, so it
 * destroys it. `h(a * a, 1)' -- the same expression in the other argument --
 * is fine and is ir/argcall.c, because there the libcall runs before anything
 * has been placed. Keeping both is what distinguishes "an argument contains a
 * call" from the hazard that actually exists. task-017. */
extern int h(int, int);

int second(int a)
{
    return h(1, a * a);
}
