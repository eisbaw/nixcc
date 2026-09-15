/* A call whose int result is discarded, which lcc lists as a root nothing
 * references -- so burg.nix reduces it to `stmt' rather than to `reg'.
 *
 * Before task-025 the table had no `stmt' rule for CALLI4 at all, so the
 * chain rule `stmt: reg' took it instead and handed a null destination to a
 * template whose text says `mv %c,a0'. The refusal that produced named the
 * template; a reader had to know burg.nix to see that the problem was a
 * discarded return value.
 *
 * Three discarded calls and a void one, and each is here for a reason:
 *
 *   put(n)      the direct form
 *   put(n + 1)  a second call, so that dropping either one changes the answer
 *   hook(n + 2) THROUGH A FUNCTION POINTER, which is the only way C reaches
 *               `stmt: CALLI4(reg)' -- the indirect row would otherwise be
 *               matched by nothing but a string comparison
 *   done()      a void call, the case that always worked, beside them
 *
 * put() returns the running total, which is NOT its argument (the driver
 * seeds it non-zero, deliberately), so a compiler that used the discarded
 * result where the argument belongs computes a different number rather than
 * the same one by luck.
 */
extern int put(int c);
extern void done(void);
extern int (*hook)(int);

int emit(int n)
{
    put(n);
    put(n + 1);
    hook(n + 2);
    done();
    return n;
}
