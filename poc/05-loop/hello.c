/* The C program the headline demo compiles, runs and prints the output of.
 *
 * Ordinary C: a global `char' array indexed by constants, digits stored a
 * byte at a time, a call whose result is thrown away. That it is ordinary is
 * the whole point -- this file was written around three backend refusals
 * until task-023, task-024 and task-025 closed them, and decision-007 is
 * where that story lives.
 *
 * `msg' holds "1..10 = " in its first eight bytes; hello() fills bytes 8, 9
 * and 10 with the sum's two digits and a newline, and writes eleven. THE
 * INDICES HERE ARE THE AUTHORITY for the message layout: driver.nix keeps a
 * guard saying the prefix must be exactly 8 bytes long, and it is this `8'
 * that it is a copy of.
 *
 * The driver defines the buffer, because this PoC selects instructions and
 * does not emit data definitions.
 *
 * wr() is the write syscall, three instructions of assembly in the driver:
 * the syscall ABI is target knowledge, not something a C program can express.
 * Its result is discarded, so nothing here notices a write that reported the
 * wrong count -- see check.nix, which says what does and what no longer does.
 */

extern int wr(int fd, char *buf, int n);
extern char msg[];

int hello(int *v, int n)
{
    int i;
    int s;

    s = 0;
    i = 0;
    while (i < n) {
        s = s + v[i];
        i = i + 1;
    }

    msg[8] = s / 10 + '0';
    msg[9] = s % 10 + '0';
    msg[10] = '\n';

    wr(1, msg, 11);
    return 0;
}
