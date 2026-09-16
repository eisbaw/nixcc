/* An expansion lands next to neighbours it was never adjacent to, and the
   TEXT has to keep them apart or it says something else entirely. `a P+ +2'
   is `a + + +2', which does not touch `a'; `a ++ +2' increments it, and both
   are valid C that compiles. Measured against gcc -E, which renders the
   first. The token streams are identical either way, so what catches this is
   the render round-trip in oracle.nix rather than the comparison with gcc.
 */
#define P +
#define M -
#define EMPTY
#define ONE 1

int a;
int plus_after = a P+ +2;
int minus_after = a M- -2;
int around_nothing = a+EMPTY+a;
int both_sides = ONE+ONE;
int parenthesised = (ONE)+(ONE);
int before_semicolon = ONE;
