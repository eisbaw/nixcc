/* The `#' operator.  C89 6.8.3.2: the argument's tokens in the spelling they
   were WRITTEN in, internal whitespace collapsed to one space, none at either
   end, and a `\' inserted before every `"' and `\' inside a string or
   character literal.

   The escaping is here rather than in cases.nix on purpose: a hand-spelled
   expectation for `"\"a\\\"b\""' is a line nobody can read and everybody
   would eventually edit to match whatever came out.  gcc is a better judge of
   it than a table is.  */

#define STR(x)          #x
#define XSTR(x)         STR(x)
#define VERSION         4
#define PAIR(a, b)      #a "/" #b

/* Whitespace: collapsed to one space inside, dropped at the ends.  */
char *plain   = STR(a + b);
char *spaced  = STR(   a     +      b   );
char *tight   = STR(a+b);
char *comment = STR(a /* not a space but treated as one */ b);

/* An empty argument is an empty literal, not a missing one.  */
char *empty   = STR();

/* Literals inside the argument, which is where the escaping lives.  */
char *quoted  = STR("quoted \" and backslash \\ inside");
char *charcon = STR('\n');
char *tickcon = STR('\'');
char *mixed   = STR(puts("hi\n"));

/* The argument of `#' is NOT macro-expanded; the two-level idiom is what
   expands it.  These two lines are the whole reason XSTR exists.  */
char *raw     = STR(VERSION);
char *cooked  = XSTR(VERSION);

/* Two `#' operators in one replacement list, with an ordinary literal
   between them: the parser joins adjacent literals, and one of these is
   manufactured.  */
char *both    = PAIR(left, right);

/* AN ARGUMENT THAT CAME OUT OF ANOTHER MACRO'S REPLACEMENT LIST.  `#' wants
   the spelling the argument was WRITTEN with, and these two are written
   inside a `#define' rather than at the use site -- so the replacement list
   has to hand its tokens on carrying their own whitespace.  An expansion that
   gave every token one space produces "file . c : 12" here, which is a wrong
   string literal with no diagnostic behind it.  Found by cross-model review;
   every other case in this file passes an argument written at the use site,
   where the trivia is the source's own.  */
#define WHERE           STR(file.c:12)
#define ARROW           STR(a->b)
char *where   = WHERE;
char *arrow   = ARROW;

/* WHO OWNS A BOUNDARY.  Four wrong string literals shipped past this file
   once, because every case above passes an argument written at the USE site
   and spells its whitespace there.  The rule they break is that trivia
   belongs to the POSITION and not to the token: an argument takes the
   boundary its PARAMETER OCCURRENCE had, a replacement list's first token
   takes the boundary of the INVOCATION it replaced, a token `##' built takes
   the boundary of its LEFT operand, and an element that expanded to nothing
   leaves its boundary behind for whatever follows.  gcc is the judge of all
   four.  */
#define SPACED(x)       STR(a x)
#define GAPPED(x)       STR(a x+b)
#define PASTED(p, q)    STR(z+p ## q)
char *spaced  = SPACED(b);              /* "a b",  not "ab"    */
char *gapped  = GAPPED();               /* "a +b", not "a+b"   */
char *pasted  = PASTED(f, oo);          /* "z+foo", not "z+ foo" */
char *inner   = XSTR(a+VERSION);        /* "a+4",  not "a+ 4"  */
char *deep    = PASTED(a+b, c);         /* "z+a+bc", not "z+a+ bc" */

/* And one that is not about ownership at all but about what whitespace IS:
   ISO C's phase 2 removes a backslash-newline without putting a space in its
   place, so neither of these has a space in it.  */
#define SPLICED         a+b
char *splice1 = STR(a+b);
char *splice2 = XSTR(SPLICED);

/* A stringified argument that itself contains a macro invocation: still not
   expanded, because it is an operand of `#'.  */
char *call    = STR(STR(inner));
char *outer   = XSTR(STR(inner));
