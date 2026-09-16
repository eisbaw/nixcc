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
