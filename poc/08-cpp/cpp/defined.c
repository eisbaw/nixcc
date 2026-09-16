/* defined() in both spellings, and combined with the logical operators. The
   operand of defined is NOT expanded: HAVE is defined as 0, so a preprocessor
   that expanded it first would ask `defined 0' instead of `defined HAVE'. */
#define HAVE 0
#define ALSO 1

#if defined HAVE
int bare_form = 1;
#else
int bare_form_wrong = 1;
#endif

#if defined(HAVE)
int paren_form = 2;
#else
int paren_form_wrong = 2;
#endif

#if !defined(MISSING)
int negated = 3;
#else
int negated_wrong = 3;
#endif

#if defined(HAVE) && defined(ALSO) && !defined(MISSING)
int combined = 4;
#else
int combined_wrong = 4;
#endif

#if defined MISSING || HAVE
int neither = 5;
#else
int neither_wrong = 5;
#endif
