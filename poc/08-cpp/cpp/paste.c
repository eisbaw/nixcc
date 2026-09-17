/* The `##' operator.  C89 6.8.3.3: the token before and the token after are
   concatenated, and "the resulting token is available for further macro
   replacement" -- which is the rule task-013.02's criterion #3 states the
   other way round, and which gcc, lcc/cpp/macro.c and the standard all agree
   on.  Half the lines below would come out differently if the pasted token
   were not rescanned, so this file is where that is settled by measurement
   rather than by argument.  */

#define CAT(a, b)       a ## b
#define CAT3(a, b, c)   a ## b ## c
#define OBJCAT          pre ## fix
#define PREFIX(n)       tmp_ ## n
#define LABEL(n)        L ## n ## _end
#define XY              42
#define ab              9
#define A               1

/* Plain pastes, of identifiers and of numbers.  */
int joined  = CAT(1, 2);
int named   = CAT(foo, bar);
int three   = CAT3(1, 2, 3);

/* The pasted token IS rescanned: `X ## Y' is `XY', which is a macro.  */
int rescan  = CAT(X, Y);
int objects = OBJCAT;
int obj2    = CAT(a, b);

/* An empty operand is a placemarker: the other side survives, and is itself
   rescanned.  `CAT(A,)' is therefore 1 and not `A'.  */
int lefty   = CAT(A, );
int righty  = CAT( , A);
int gone[]  = { CAT( , ) 5 };

/* The operand of `##' is NOT macro-expanded first: this is `Ax', not `1x'.  */
int unexpanded = CAT(A, x);

/* Pastes that make punctuators rather than identifiers, and a rendered
   result that sits next to a token it was never adjacent to.  */
int counter;
void bump(void)
{
    counter CAT(+, +);
    counter = 1 CAT(+, +)+ 2;
}

/* The idiom real code uses: a name built from an argument.  */
int PREFIX(one) = 11;
int PREFIX(two) = 22;
int LABEL(3) = 33;

/* A paste whose result would name the macro being expanded is painted, so it
   stops rather than expanding for ever.  */
#define SELF            CAT(SE, LF)
int painted = SELF;

/* `##' in an OBJECT-LIKE replacement list is legal too, and pastes the same
   way.  */
#define OBJ3            a ## b ## c
int objthree = OBJ3;
