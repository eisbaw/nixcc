/* Exactly one arm of a chain fires, and it is not the first or the last --
   a chain that always took the first arm, and one that fell through to the
   #else, would both be caught. */
#define LEVEL 3

#if LEVEL == 1
int one = 1;
#elif LEVEL == 2
int two = 2;
#elif LEVEL == 3
int three = 3;
#elif LEVEL == 4
int four = 4;
#else
int other = 5;
#endif

/* And a chain whose later arms are TRUE as well: only the first true one
   fires, so a preprocessor that failed to record `taken' would emit two. */
#if LEVEL > 10
int gt_ten = 6;
#elif LEVEL > 2
int gt_two = 7;
#elif LEVEL > 1
int gt_one = 8;
#else
int small = 9;
#endif
