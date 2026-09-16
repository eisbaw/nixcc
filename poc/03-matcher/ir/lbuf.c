/* A LOCAL array at a constant index, which is the other half of ir/gsym.c.
 *
 * lcc folds a constant subscript of a global into the SYMBOL -- `ADDRGP4
 * tbl+4' -- and gsym.c pins that. A constant subscript of a LOCAL cannot be
 * folded that way, because the frame is not laid out until gencode runs, so it
 * becomes an `address' code item and arrives here as `ADDRLP4 buf+3': a FRAME
 * symbol with a displacement, which the emitter has to add to the slot rather
 * than look up as a name of its own.
 *
 * The three constant indices hold three different values and are weighted 2, 4
 * and 8, so a displacement that is dropped, applied to the wrong element or
 * added to the wrong base changes the answer rather than only the addresses --
 * with every index collapsed to zero the return is 15 * buf[0] instead of 293.
 *
 * `n' is part of the test: the loop fills the array from it, so a compiler
 * that ignored the argument would not get 293 by luck.
 */
int pack(int n)
{
    char buf[8];
    int i;

    i = 0;
    while (i < 8) {
        buf[i] = i + n;
        i = i + 1;
    }
    buf[3] = 100;
    buf[5] = 7;
    return buf[0] + buf[3] * 2 + buf[5] * 4 + buf[7] * 8;
}
