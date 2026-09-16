/* #if arithmetic and C operator precedence. Each test is written so that the
   WRONG precedence gives the other answer: 1+2*3 is 7 and not 9, 8/4/2 is 1
   and not 4, and 1<<2+1 is 8 and not 5. */
#if 1 + 2 * 3 == 7
int prec_mul = 1;
#else
int prec_mul_wrong = 1;
#endif

#if 8 / 4 / 2 == 1
int assoc_div = 2;
#else
int assoc_div_wrong = 2;
#endif

#if (1 + 2) * 3 == 9
int parens = 3;
#else
int parens_wrong = 3;
#endif

#if 17 % 5 == 2
int modulo = 4;
#endif

#if -7 / 2 == -3 && -7 % 2 == -1
int truncation = 5;
#else
int truncation_wrong = 5;
#endif

#if (2 ? 10 : 20) == 10 && (0 ? 10 : 20) == 20
int ternary = 6;
#else
int ternary_wrong = 6;
#endif

#if !0 && !!7
int logical_not = 7;
#endif

#if (6 & 3) == 2 && (6 | 3) == 7 && (6 ^ 3) == 5 && (~0 & 15) == 15
int bitwise = 8;
#else
int bitwise_wrong = 8;
#endif

#if 3 > 2 && 2 >= 2 && 1 < 2 && 2 <= 2 && 1 == 1 && 1 != 2
int relational = 9;
#else
int relational_wrong = 9;
#endif
