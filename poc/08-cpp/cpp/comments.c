/* A comment is whitespace. One spanning a newline inside a directive does
   NOT end the directive; one outside a directive DOES end a logical line, so
   a `#' after it starts one. Both halves were measured against gcc -E.

   A `//' comment before a directive is the same question again, but `gcc
   -std=c89' rejects `//' outright, so that case is in cases.nix rather than
   here -- it cannot be part of a differential whose reference refuses it. */
#define BODY /* leading */ 40 /* trailing */
#define SPLIT /* this comment
                 spans a newline and the directive continues */ 50

int body = BODY;
int split = SPLIT;

int before = 1; /* a comment that
                   spans lines */
#define AFTER_COMMENT 60
int after = AFTER_COMMENT;

/* a leading comment
   spanning lines */
#define AFTER_LEADING 70
int leading = AFTER_LEADING;
