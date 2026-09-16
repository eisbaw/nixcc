/* Character constants are integer constant expressions, and plain char is
   signed on this target, so '\377' is -1 rather than 255. */
#if 'a' == 97 && 'A' == 65
int letters = 1;
#else
int letters_wrong = 1;
#endif

#if '\n' == 10 && '\t' == 9 && '\0' == 0
int escapes = 2;
#else
int escapes_wrong = 2;
#endif

#if 'z' - 'a' == 25
int arithmetic = 3;
#else
int arithmetic_wrong = 3;
#endif
