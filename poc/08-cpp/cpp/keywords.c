/* To the preprocessor a keyword is just an identifier, so a macro body may
   be keywords and a macro may be named after one. That is legal C89 and the
   lexer classifies `int' as a keyword token, not as an identifier, so this
   is the case where matching on the token KIND rather than its TEXT breaks. */
#define INTEGER int
#define CONSTANT const
#define signed unsigned

INTEGER plain = 1;
CONSTANT INTEGER constant = 2;
signed INTEGER converted = 3;

#ifdef signed
int keyword_is_a_macro = 4;
#else
int keyword_is_not_a_macro = 4;
#endif
