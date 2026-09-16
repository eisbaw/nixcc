/* String literals: the lit segment, the join, and the byte list.
 *
 * WHAT IS BEING PINNED HERE, form by form.
 *
 *   * ADJACENT literals are ONE literal with ONE terminator. `"one" "two"' is
 *     seven bytes, not eight: task-011's evaluator returns a literal's units
 *     with no NUL precisely so the parser can join first and terminate once.
 *
 *   * The SAME literal twice is ONE definition. lcc interns constants, so both
 *     `"abc"' below reach the same generated symbol and the listing carries
 *     one `defstring' with a reference count of two. A frontend that emitted
 *     two would still run correctly and would waste the bytes in silence.
 *
 *   * An EMBEDDED NUL survives. `"a\0b"' is four bytes, and a Nix string
 *     cannot hold the middle one -- decision-001 -- which is why a decoded
 *     literal is a byte list from the lexer to the .data and why `defstring'
 *     prints it as `\000'.
 *
 *   * A byte ABOVE 127 reaches the listing through `\377', which is also the
 *     only way it can: poc/06-constants has no table entry for a source byte
 *     above ASCII and throws rather than inventing one (task-046).
 *
 *   * A WIDE literal is not a byte list at all. widechar is `unsigned short'
 *     on this target, so its units go down as `defconst unsigned.2' one at a
 *     time and the endianness is the assembler's problem (decision-004).
 *
 *   * And a literal SUBSCRIPTED BY A CONSTANT is the one form that made
 *     task-032 necessary: it folds into `ADDRGP4 2+4', a numeric base with a
 *     displacement, which is neither a name nor a label the obvious reading
 *     of either would accept.
 */
char *joined(void)
{
    return "one" "two";
}

int shared(int i)
{
    char *a;

    a = "abc";
    return a[i] + "abc"[1] + "abcdefgh"[4];
}

int bytes(int i)
{
    return "a\0b"[2] + "\377\001"[i] + "tab\there"[3] + "q\"\\z"[i];
}

unsigned short wide(int i)
{
    unsigned short *w;

    w = L"wide";
    return w[i];
}
