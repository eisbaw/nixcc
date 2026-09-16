/* #undef makes a name ordinary again, and a name may be defined afresh
   afterwards with a DIFFERENT body -- which is the only way to tell an
   #undef that worked from one that did nothing. */
#define SIZE 11
int a = SIZE;
#undef SIZE
int b = SIZE;
#define SIZE 22
int c = SIZE;
#undef SIZE
#undef SIZE
int d = SIZE;
