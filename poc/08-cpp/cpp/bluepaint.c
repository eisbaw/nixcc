/* The blue paint of C89 6.8.3.4: a macro is not re-expanded inside its own
   expansion, directly or indirectly.  Every line here would loop for ever if
   the hide set never hid, and each leaves a DIFFERENT name standing, which is
   what tells one broken hide set from another in the token stream.

   WHAT IS NOT HERE, said plainly rather than claimed the other way round: a
   case that discriminates HIDING TOO MUCH.  In every case below the macro
   name and its closing parenthesis arrive from the same context, which is
   exactly where C89's `HS(name) INTERSECT HS(rparen)' is a no-op -- so none
   of them can see that this preprocessor does not compute the intersection.
   The shape that would is `#define f(a) a*g' with `#define g(a) f(a)' and
   `f(2)(9)', where gcc expands one level further than we do.  It is a known
   divergence, it is pinned in cases.nix with our answer, and task-080 is
   where it is fixed -- at which point the case belongs in THIS file.  */

#define SELF            SELF
#define PING            PONG
#define PONG            PING
#define OUTER           INNER + OUTER
#define INNER           5

int a = SELF;
int b = PING;
int c = OUTER;

/* The same three questions with parameters.  `REC(2)' leaves `REC' standing
   next to its own argument list, which is a stronger statement than `REC'
   alone: the argument was substituted and the name was not re-invoked.  */
#define REC(x)          REC(x) + 1
#define FPING(x)        FPONG(x)
#define FPONG(x)        FPING(x)

int d = REC(2);
int e = FPING(7);

/* A painted name FOLLOWED BY `(' is not an invocation -- the paint wins over
   the parenthesis.  `ID(ID)' hands back `ID', and the `(7)' after it stays
   where it is.  */
#define ID(x)           x
int f = ID(ID)(7);

/* Paint on a token that `##' manufactured, which is the case the frame-level
   hide set of a simpler implementation gets wrong.  */
#define CAT(p, q)       p ## q
#define BUILT           CAT(BUI, LT)
int g = BUILT;

/* And paint that survives an argument being expanded before substitution:
   the argument of `WRAP' expands to `H', which is hidden inside H's own
   expansion and must stay hidden through the substitution.  */
#define WRAP(x)         [x]
#define H               WRAP(H)
int h[] = H;

/* An argument naming the macro it is an argument of.  gcc leaves the inner
   one alone because it is painted by the time it is rescanned.  */
int i = ID(ID(3));
