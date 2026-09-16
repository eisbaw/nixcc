/* Struct types, reached every way slice 4a can reach them.
 *
 * THE LAYOUT HERE IS THE ORACLE'S AND NOT RV32's. symbolicIR's structmetric
 * is { size = 0, align = 4 }, so every struct starts four-byte aligned --
 * `struct { char a; char b; }' is four bytes, not two. decision-009 records
 * the same kind of divergence about argument passing. Both are reproduced
 * rather than corrected, because the diff is against lcc.
 *
 * `struct P' is char-then-int so that the padding is in the offsets: `i' is
 * at 4 and not at 1, and every `q->i' in the listing says so. `struct Q'
 * nests one struct inside another and puts an array after it, so the member
 * offsets are the sum of three different alignment decisions rather than one.
 *
 * ASGNB AND INDIRB HAVE NO ROW IN poc/03-matcher/rules.nix and this file
 * emits both, deliberately. cases.nix's opcode list is a claim about the
 * FRONTEND -- it says so -- and CALLP4 has held the same position since
 * task-054 put it there, with task-057 as the task that lifts it. A struct
 * copy is lowered correctly here and refused loudly at instruction selection;
 * task-060 is where the backend learns to make one, and run/records.c is
 * written not to need it.
 *
 * `volat' is the one case no other file can reach: dag.c builds the load of
 * a struct with a VOLATILE member with newnode rather than node, so two
 * copies of `x' stay two INDIRB nodes instead of one shared node with
 * count=2. Nothing but the listing shows it.
 */
struct P {
    char c;
    int  i;
};

struct Q {
    struct P p;
    short    h;
    char     tail[3];
};

struct V {
    volatile int a;
    int          b;
};

int through(struct P *p)
{
    p->c = 1;
    p->i = p->c + 2;
    return p->i;
}

int nest(struct Q *q)
{
    struct P a;

    a.c = 3;
    a.i = 4;
    q->p = a;
    q->h = a.i;
    q->tail[1] = a.c;
    return q->p.i + q->tail[0] + sizeof(struct Q);
}

int arrays(void)
{
    struct P a;
    struct P m[2];

    a.c = 5;
    a.i = 6;
    m[0] = a;
    m[1] = m[0];
    return m[1].i + sizeof(struct P) + sizeof m;
}

int byvalue(struct P v)
{
    return v.i;
}

int pass(struct P *p)
{
    return byvalue(*p);
}

/* An aggregate with NO tag. Two things live here and nothing else in the
 * corpus holds either. First the spelling: with no tag to name it after, lcc
 * names it after the line it was defined on -- `struct defined at N', and the
 * listing carries the number. Second, and far less visible, THE NAME IS A
 * GENERATED LABEL NUMBER, so declaring this consumes a label and every label
 * after it in the translation unit shifts -- including `volat''s return label
 * below, which is in a different function. A frontend that named anonymous
 * tags any other way would renumber the rest of the file. */
int anon(void)
{
    struct { int a; char b; } x;

    x.a = 7;
    x.b = 1;
    return x.a + x.b + sizeof x;
}

int volat(void)
{
    struct V x;
    struct V w;
    struct V y;

    w = x;
    y = x;
    return w.a + y.b + x.b + x.b;
}
