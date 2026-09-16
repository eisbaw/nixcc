/* Nesting, and the case that separates a real conditional stack from a
   counter: an inner #if that is TRUE inside an outer group that is FALSE
   must stay silent, and its #else must stay silent too. */
#define OUTER 0
#define INNER 1

#if OUTER
  #if INNER
int outer_off_inner_on = 1;
  #else
int outer_off_inner_else = 2;
  #endif
int outer_off_tail = 3;
#else
  #if INNER
int outer_else_inner_on = 4;
  #else
int outer_else_inner_else = 5;
  #endif
int outer_else_tail = 6;
#endif

#if !OUTER
  #if !INNER
int both_flipped = 7;
  #else
int flipped_else = 8;
  #endif
#endif
