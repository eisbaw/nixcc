/* Signedness in #if. An unsigned operand drags the comparison with it, so
   -1 < 0 is true and -1 < 0u is false; that is the whole point of the usual
   arithmetic conversions and it is invisible to a table of positive values.
   Every value here is small enough that a 32-bit and a 64-bit #if agree. */
#if -1 < 0
int signed_compare = 1;
#else
int signed_compare_wrong = 1;
#endif

#if -1 < 0u
int unsigned_compare_wrong = 2;
#else
int unsigned_compare = 2;
#endif

#if -1 > 0u
int unsigned_wraps = 3;
#else
int unsigned_wraps_wrong = 3;
#endif

#if (7u / 2u) == 3 && (7u % 2u) == 1
int unsigned_divide = 4;
#endif

#if 10L == 10 && 10UL == 10u
int suffixes = 5;
#endif

/* A negative left operand is the only thing that separates an unsigned
   divide from a signed one: as unsigned, -1 is 4294967295 and the quotient
   is large; as signed, -1 / 2 truncates toward zero and is 0. The positive
   pair above gives the same answer either way and so tests nothing. Both
   forms are written as COMPARISONS rather than equalities, because the
   quotient itself differs between a 32-bit #if and a 64-bit one. */
#if (-1 / 2u) > 1
int unsigned_divide_converts = 6;
#else
int unsigned_divide_converts_wrong = 6;
#endif

#if (-1 % 2u) == 1
int unsigned_remainder_converts = 7;
#else
int unsigned_remainder_converts_wrong = 7;
#endif
