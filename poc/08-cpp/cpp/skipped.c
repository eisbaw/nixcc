/* A skipped group is not evaluated at all: its #if operands need not make
   sense, and directives that would otherwise be refused are inert. This is
   what lets #if 0 fence off text. */
#if 0
#if MISSING_MACRO_WITH_NO_VALUE ==
int not_even_parsable = 1;
#endif
#error this must never fire
#pragma something we do not implement
#include <nowhere.h>
#define NEVER 1
#endif

#ifdef NEVER
int never_defined = 2;
#else
int never_stayed_undefined = 3;
#endif

#if 0
#else
int else_of_a_false_if = 4;
#endif

#if 1
int plain_true = 5;
#endif
