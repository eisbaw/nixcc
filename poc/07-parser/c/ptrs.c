/* Subscripting and pointer arithmetic: the whole of what slice 2 added to the
 * tree constructors, and the reason `a[i]' is not an addition.
 *
 * WHAT EACH GROUP IS FOR, because a file of pointer expressions all looks the
 * same and the interesting ones are not the obvious ones.
 *
 *   * A CONSTANT subscript of a global does not become an add at all. simp.c's
 *     addrtree folds it into the symbol -- `ADDRGP4 tbl+8' -- and prints an
 *     `address' line ABOVE the function, before `export'. A constant subscript
 *     of a LOCAL cannot be named that early, because the frame is laid out
 *     later, so it becomes an Address CODE ITEM and its `address' line appears
 *     in the middle of the body. Those are two different code paths with one
 *     spelling in C, and both are here.
 *
 *   * `p[i + 1]' and `p[1 + i]' reassociate so the constant meets the address,
 *     and `(p + 1)[2]' folds two constants into one. Each is a separate rule
 *     in simp.c's ADD+P chain, and a chain whose rules are never selected is
 *     asserted by nothing.
 *
 *   * `q - p' between two pointers is neither an add nor a subtract: it is an
 *     UNSIGNED subtraction cast to long and divided by the element size, which
 *     is three opcodes nothing else in this corpus produces.
 *
 *   * `m[1][2]' subscripts an array OF arrays. The inner subscript yields the
 *     inner ARRAY, not a load, and that is the two lines at the end of expr.c's
 *     `[' arm that look like they could be dropped.
 */
extern int tbl[8];
extern char cbuf[];
extern int take(char *p, int n);

int use(int i, int *p)
{
    int m[3][4];
    char local[8];
    int *q;
    long d;

    q = tbl + 2;
    q = q - 1;
    q = 3 + q;
    d = q - tbl;

    local[0] = 'a';
    local[i] = 'b';
    m[1][2] = i;
    m[i][i] = m[2][1];

    return tbl[1] + tbl[i] + tbl[i + 1] + tbl[1 + i]
        + (tbl + 1)[2] + *(tbl + i) + *(i + tbl) + *(q - 2)
        + cbuf[2] + cbuf[i] + local[1] + p[i] + p[3]
        + m[0][0] + (int) d;
}

/* An int stored THROUGH a char lvalue is a CVII1 the loads above never
 * produce -- lcc narrows on the way in and widens on the way out, and only the
 * store carries the narrowing conversion. Passing an array to a function is
 * the other half: the array decays to an ARGP4, which is the only opcode here
 * that crosses a call boundary. */
int store(int i)
{
    char local[4];

    local[0] = i;
    local[1] = i + 1;
    cbuf[2] = i;
    return take(local, i) + take(cbuf, 2);
}

/* The NULL POINTER CONSTANT, which is a pointer constant and therefore the one
 * CNST+P a C program can write. `p = 0' is not a special case in lcc: the zero
 * is converted int -> unsigned -> pointer and simp.c folds the whole chain
 * into `CNSTP4 0', whose NAME is `0' and not `0x0' -- lcc's own `%p' prints
 * the `0x' only for a non-null pointer, and that name is what the listing
 * carries.
 *
 * `(char *)8 - (char *)2' is the other end of the same machinery and reads
 * oddly on purpose: the fold produces a POINTER constant holding a byte
 * difference, which is what simp.c does and not what a reader would write. */
int nulls(char *a, unsigned u)
{
    char *p;
    char *z;

    p = 0;
    z = (char *) u;
    return (p == 0) + (a != 0) + (int) (char *) 4000000000u
        + (int) ((char *) 0 + 3) + (int) ((char *) 8 - (char *) 2) + *z;
}
