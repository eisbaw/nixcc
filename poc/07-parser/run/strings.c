/* Criterion #3 and #2 of task-028, in one program: a char array, a string
 * literal, and an EMBEDDED NUL that has to survive to the running machine.
 *
 * THE LITERAL IS THE TEST. `"ab" "\0cd"' is five units and one terminator --
 * a, b, NUL, c, d, NUL -- and every plausible way of getting it wrong changes
 * what this prints:
 *
 *   * terminate each literal separately and it is a,b,NUL,NUL,c,d,NUL, so the
 *     loop below copies `ab--c' instead of `ab-cd';
 *   * stop at the NUL, as a `char *' in C normally would, and bytes 3 and 4
 *     are whatever followed in .data;
 *   * lose the join and it is `ab' and three bytes of the next definition.
 *
 * The NUL itself is written out as `-', because stdout is compared against a
 * Nix string and a Nix string cannot hold a NUL (decision-001). What proves
 * the NUL was THERE is that the two bytes after it are `c' and `d'.
 *
 * `n' IS PART OF THE TEST, not decoration. A program whose output does not
 * depend on the argument the driver passes cannot tell a compiler that runs it
 * from one that ignores it -- ir/unsig.c's divisor of 7 is the worked example
 * of that mistake, and it cost a whole cycle. The two digits assume 10 <= n
 * <= 99; cases.nix holds that assumption as a guard rather than a comment.
 */
extern int wr(int fd, char *buf, int n);

int run(int n)
{
    char buf[16];
    char *s;
    int i;
    int k;

    s = "ab" "\0cd";
    i = 0;
    k = 0;
    while (i < 5) {
        if (s[i] == 0)
            buf[k] = '-';
        else
            buf[k] = s[i];
        k = k + 1;
        i = i + 1;
    }
    buf[k] = n / 10 + '0';
    buf[k + 1] = n % 10 + '0';
    buf[k + 2] = '\n';
    wr(1, buf, k + 3);
    return 0;
}
