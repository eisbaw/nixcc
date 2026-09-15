/* The C program the headline demo compiles, runs and prints the output of.
 *
 * It is written against what poc/03-matcher's rule table actually implements
 * -- 4-byte integers and pointers, loads, stores, a while loop, the
 * multiply/divide libcalls and a call -- and nothing else. There are no chars
 * in it because there is no rule for a byte load or store yet (task-024), so
 * the message is built a WORD at a time: four ASCII codes packed
 * little-endian into one int, which is why the digits are shifted into place
 * rather than stored one by one.
 *
 * `out' is the message buffer, passed in rather than referred to as a global,
 * because lcc folds `msg[2]' into `ADDRGP4 msg+8' and neither the matcher nor
 * the assembler understands a symbol with a constant offset yet (task-023).
 * The driver passes the address of a .data buffer that already holds
 * "1..10 = " in its first two words; this function fills the third with the
 * sum's two decimal digits and a newline, and asks wr() to write 11 bytes.
 *
 * wr() is the write syscall, three instructions of assembly in the driver:
 * the syscall ABI is target knowledge, not something a C program can express.
 */

extern int wr(int fd, int *buf, int n);

int hello(int *v, int n, int *out)
{
    int i;
    int s;

    s = 0;
    i = 0;
    while (i < n) {
        s = s + v[i];
        i = i + 1;
    }

    /* "55\n" and a trailing NUL that is never written: wr() is given 11
     * bytes, not 12. A Nix string could not hold that NUL (decision-001);
     * a byte list can, which is the whole reason this loop closes in Nix. */
    out[2] = (s / 10 + 48) + ((s % 10 + 48) << 8) + (10 << 16);

    /* The result is USED because checking write()'s return value is what a
     * C program should do. It was not a free choice when this was written --
     * a discarded int result had no rule in the matcher's table and was
     * refused -- but task-025 has since added one, so the contortion is gone
     * and only the good reason is left. Exit status 0 therefore means "the
     * write syscall reported all eleven bytes written". */
    if (wr(1, out, 11) == 11)
        return 0;
    return 1;
}
