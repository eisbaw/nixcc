/* Object-like macros: a body of several tokens, a body that names another
   macro, an empty body, and a macro whose name also appears as an ordinary
   identifier so that only the DEFINED one is replaced. */
#define WIDTH 32
#define HALF (WIDTH / 2)
#define BOTH WIDTH + HALF
#define NOTHING
#define PUNCT >=

int width = WIDTH;
int half = HALF;
int both = BOTH;
int scaled = WIDTH * HALF;
int NOTHING plain = 1;
int cmp = (WIDTH PUNCT HALF);

/* WIDTHS is a different identifier and must survive untouched. */
int WIDTHS = 1;
int widthless = 0;
