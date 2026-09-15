/* A global array indexed by a CONSTANT, which lcc folds into one node:
 * `tbl[1]' becomes `ADDRGP4 tbl+4', a symbol with a displacement, and
 * nothing in the rule table splits it -- the assembler resolves it
 * (task-023). Two different indices, and a store as well as a load, so a
 * displacement that were dropped or applied to the wrong element changes the
 * answer rather than merely the addresses. */
extern int tbl[4];

int pick(int n)
{
    tbl[1] = n;
    tbl[3] = tbl[1] + tbl[2];
    return tbl[3] - tbl[0];
}
