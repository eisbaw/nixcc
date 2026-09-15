/* char and short: the byte and halfword loads and stores, the conversions
 * lcc wraps around every one of them, and both source widths of CVII4.
 *
 * WHAT THIS DOES NOT TEST, and cannot until task-033. lcc promotes every
 * narrow load, so an INDIRI1 always arrives under a CVII4 and an INDIRU1
 * under a CVUI4 -- and those lower to a shift pair and a mask that
 * RE-NORMALISE the register. `lb' followed by slli/srai and `lbu' followed by
 * slli/srai leave the same 32 bits, so swapping the two loads changes nothing
 * this function returns. Measured, not assumed: the whole table with lb and
 * lbu exchanged still exits 1679. The sign the load carries is checked
 * against the RULE TABLE instead, by cases.nix's `narrowLoads'.
 *
 * sbuf and ubuf still hold the same four bytes and shalf and uhalf the same
 * halfword, with the high bit set, because that is what makes the SIGNED and
 * UNSIGNED conversions -- srai against andi, which is what the table really
 * chooses between today -- produce different numbers from identical memory.
 */
extern signed char sbuf[];
extern unsigned char ubuf[];
extern short shalf[];
extern unsigned short uhalf[];

int scan(int n)
{
    int i;
    int s;
    unsigned u;

    s = 0;
    i = 0;
    while (i < n) {
        s = s + sbuf[i] + ubuf[i];
        i = i + 1;
    }

    s = s + shalf[0] + uhalf[0];

    sbuf[0] = 7;
    sbuf[2] = s;
    ubuf[1] = s;
    shalf[1] = s;
    uhalf[1] = s;

    u = ubuf[1];
    return s + sbuf[0] + sbuf[2] + shalf[1] + (int) u + uhalf[1];
}
