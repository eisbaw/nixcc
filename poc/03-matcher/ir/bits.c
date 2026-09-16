/* The bitwise, shift and unary operators, each in both the form RV32I has an
 * instruction for and the form it has an immediate for (task-051).
 *
 * `b' is loaded once and used by several of the register forms, so the
 * common-subexpression register is exercised across them; the immediate forms
 * sit beside them so that `and'/`andi' are distinguished by which rule fired
 * and not only by the answer.
 *
 * THE SHIFTS ARE HERE FOR THE UNSIGNED CASE'S SAKE as much as for their own.
 * ir/unsig.c pins RSHU4 to `srl'; what says that is not the same instruction
 * as RSHI4's is a rule table in which RSHI4 is `sra' -- and before this file
 * had a signed `>>', no corpus node selected reg_rshi_imm or reg_rshi_reg at
 * all, so that half of the pair was asserted only by a table describing
 * itself. The right shifts are applied to `a', which the driver makes
 * NEGATIVE, so `sra' and `srl' give different answers here; the left shifts
 * are applied to `b', which is positive, because shifting a negative value
 * left is not something C defines.
 *
 * `~x' and `-x' are the two RV32I has NEITHER for. Both are written as
 * arithmetic in the rule table -- `xori' with all ones and `sub' from the zero
 * register -- so they are here to prove that arithmetic computes what C says
 * it does, and not merely that something was emitted.
 *
 * The last two `if's are the two signed comparisons no other corpus file
 * reaches: lcc inverts the test that skips the body, so `<=' arrives as GTI4
 * and `==' as NEI4.
 */
int mask(int a, int b)
{
    int x;

    x = a & b;
    x = x | 16;
    x = x ^ b;
    x = x & 255;
    x = x | b;
    x = x ^ 3;
    x = x + (a >> 2);
    x = x + (b << 3);
    x = x + (a >> (b & 7));
    x = x + (b << (a & 3));
    x = ~x;
    x = -x;
    if (x <= b)
        x = x + 7;
    if (x == b)
        x = x + 11;
    return x;
}
