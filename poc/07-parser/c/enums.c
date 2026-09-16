/* Enumerations: the constants, the type, and the two places lcc treats an
 * enum as an `int' rather than as itself.
 *
 * THE VALUES ARE THE TEST. `A = 1' then a bare `B' is 2, and `C = 10' then a
 * bare `D' is 11, so the implicit counter has to RESUME from the explicit
 * value rather than count positions. An enumerator numbered by its position
 * would make B 1 and D 3; a counter that an explicit value did not advance
 * would make both of them 0. Either way the listing says so, in the CNSTI4
 * operands, and run.sh corrupts the counter to prove it is read.
 *
 * WHERE THE `int' SHOWS THROUGH, and neither is obvious from the C:
 *
 *   * types.c's deref() ends `return isenum(ty) ? unqual(ty)->type : ty', so
 *     loading an `enum E' variable is an INDIRI4 of an `int'. Without that
 *     line every enum lvalue reaches enode.c with a type isarith() rejects,
 *     and `e + 1' is a type error on ordinary C.
 *   * enode.c's assign() and calltree() both reduce an enum to its underlying
 *     type, which is why `enum E next(enum E)' returns RETI4 and not
 *     something of its own.
 *
 * The enum's own SIZE is `int''s, and `sizeof' is what says so.
 */
enum E { A = 1, B, C = 10, D };

enum E next(enum E e)
{
    if (e == A)
        return D;
    return e;
}

int use(int n)
{
    enum E e;
    int    k;

    e = B;
    k = e + n;
    if (next(e) == D)
        k = k + C;
    return k + A + D + sizeof(enum E) + sizeof e;
}
