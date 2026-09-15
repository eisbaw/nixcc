/* Diagnostics about DECLARATIONS rather than about expressions.
 *
 * Every function below compiles, in both frontends, to the same IR. The only
 * place the difference between lcc's answer and ours could ever show is lcc's
 * stderr -- so a frontend that simply did not implement these four warnings
 * would pass a node-for-node IR diff with nothing to say about it. That is the
 * gap criterion #7 exists to close, and warns.c only covers the expression
 * half of it.
 */
extern int a(void);
static int a(void);

int b(void);
static int b(void);

extern int g(int, int);

int f(void)
{
    register volatile int r;
    extern int g(void);

    r = 1;
    return r;
}

int h(void)
{
    extern int j(int, int);
    return j(1, 2);
}

/* The two places lcc consults eqtype() rather than type identity. An
 * unprototyped `int k()' is COMPATIBLE with `int k(int)' -- C says so, because
 * `int' is already its own promoted type -- so lcc says nothing about either
 * of these. A frontend that compared types structurally would invent a warning
 * on both, which is a criterion #7 failure pointing the other way: not a
 * diagnostic dropped, a diagnostic made up. */
int uses(void)
{
    extern int k(int);
    return k(1);
}

int implicit(void)
{
    return k(1);
}

int redeclares(void)
{
    extern int k();
    return k(2);
}
