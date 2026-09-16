/* Backslash-newline. A continued directive is one logical line; a
   continuation between two tokens of ordinary text is just whitespace. */
#define LONG 1 + \
             2 + \
             3
#define SPREAD \
  10 \
  + 20

int folded = LONG;
int spread = SPREAD;
int plain = 1 + \
            2;
#if LONG \
    == 6
int continued_condition = 1;
#else
int continued_condition_wrong = 1;
#endif
