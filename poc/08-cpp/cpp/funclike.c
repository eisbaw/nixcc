/* Function-like macros: parameters, arguments, and what counts as an
   invocation at all.  Every line here has `gcc -std=c89 -E -P' as its oracle,
   so nothing below is a claim this project makes on its own.

   The cases are chosen against the failure ir/unsig.c taught: a macro that
   expands to the tokens it started as, or an argument that is the same on
   both sides of a substitution, discriminates nothing.  So the arguments
   differ from each other and from the body they land in.  */

#define MAX(a, b)       ((a) > (b) ? (a) : (b))
#define MIN(a, b)       ((a) < (b) ? (a) : (b))
#define SQUARE(x)       ((x) * (x))
#define APPLY(f, v)     f(v)
#define NOTHING()
#define SECOND(a, b)    b
#define FIRST(a, b)     a
#define IDENT(x)        x
#define SCALE           3
#define LP              (

/* Nested invocations, and an argument that is itself an invocation.  */
int clamp(int v, int lo, int hi)
{
    return MIN(MAX(v, lo), hi);
}

/* An object-like macro inside a function-like body.  */
int area(int s)
{
    return SQUARE(s) * SCALE;
}

/* A macro name passed AS an argument and then invoked by the body.  */
int twice(int n)
{
    return APPLY(SQUARE, n) + APPLY(IDENT, n);
}

/* A comma inside parentheses belongs to the argument it sits in, and the
   argument keeps those parentheses when it is substituted.  */
int pair(void)
{
    return SECOND((1, 2), 3) + FIRST(4, (5, 6));
}

/* An empty replacement list, and an empty argument.  */
int blank(void)
{
    NOTHING()
    return SECOND(, 7);
}

/* A function-like macro name that is not followed by `(' is an ordinary
   identifier -- and a `(' that a macro would EXPAND to is not the `(' of an
   invocation either, because the test is on the raw next token.  */
int MAX = 4;
int notacall(void)
{
    return IDENT LP 8 ) + MIN;
}

/* An argument used twice, with a side-effecting spelling that makes the
   duplication visible in the token stream.  */
#define DOUBLE(x)       ((x) + (x))
int doubled(int k)
{
    return DOUBLE(k * 2);
}

/* Deep nesting of invocations inside arguments.  */
int deep(int q)
{
    return IDENT(IDENT(IDENT(SQUARE(q))));
}
