/* The two arms emit DIFFERENT tokens, so a conditional that always chose the
   first arm and one that always chose the second are distinguishable. */
#define ON 1
#ifdef ON
int have_on = 111;
#else
int lack_on = 222;
#endif

#ifdef OFF
int have_off = 333;
#else
int lack_off = 444;
#endif

#ifndef OFF
int no_off = 555;
#else
int yes_off = 666;
#endif

#ifndef ON
int no_on = 777;
#endif
int tail = 888;
