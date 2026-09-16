/* A macro is not re-expanded inside its own expansion. Each of these would
   otherwise not terminate, and each leaves a DIFFERENT name standing, so a
   hide set that leaked would be visible in the output rather than as a hang. */
#define SELF SELF
#define PING PONG
#define PONG PING
#define OUTER INNER + OUTER
#define INNER 5

int self = SELF;
int ping = PING;
int pong = PONG;
int outer = OUTER;
int inner = INNER;
