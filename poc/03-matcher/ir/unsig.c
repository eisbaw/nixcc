/* The U-typed opcodes (task-051): every one of them, and every RULE for every
 * one of them, on data whose top bit is set -- because that is the only place
 * the unsigned rules and their signed twins disagree.
 *
 * WHY THE ARGUMENTS ARE WHAT THEY ARE. drivers/unsig.s passes a = 0xfffffff0
 * and b = 9. Read as a signed integer a is -16, so every fork below answers
 * differently if the table picks the I-typed rule:
 *
 *   a / b and a % b   __udivsi3/__umodsi3 say 477218586 and 6; __divsi3 and
 *                     __modsi3 say -1 and -7.
 *   a >> 3, a >> b    `srl' says 0x1ffffffe; `sra' says 0xfffffffe.
 *   the comparisons   a > b and a >= b are true unsigned and false signed,
 *                     and the four `if's add four different amounts, so a
 *                     `blt' where `bltu' belongs moves the answer rather than
 *                     only the branch.
 *
 * b IS 9 AND NOT 7, and the difference is not cosmetic. With b = 7 an earlier
 * version of this program returned the same number whether DIVU4 called
 * __udivsi3 or __divsi3: the quotients differ, but `x = x * b' and then
 * `x = x & a' -- which clears the low four bits -- happened to carry the
 * difference away. Measured, not reasoned: the divide mutation ran and the
 * exit code did not move. b was chosen by checking that each of the
 * signed-for-unsigned substitutions changes this program's answer, which is
 * the property the case exists for and not one that follows from having
 * unsigned operands.
 *
 * EVERY BINARY OPERATOR APPEARS TWICE, once against a register and once
 * against a constant, because those are two RULES and not one. Review found
 * the first version of this file exercising only one side of `&', `|', `^',
 * `<<' and `>>'. The other five rows were reachable, named in the rule table,
 * and pinned by a mnemonic check that never consults the corpus -- so they
 * could be changed to the wrong instruction with the whole suite still green,
 * which was demonstrated rather than supposed. A rule covered only by a table
 * that describes it is not covered.
 *
 * THE IMMEDIATE FORMS RUN ON `y' AND NOT ON `x', which is not tidiness: a
 * 12-bit immediate mask applied to x would throw away the high bits that make
 * every fork above visible, and the rest of the program would then discriminate
 * nothing. y is seeded from a % b so that its low bits vary, and the three
 * constants are chosen so that no two of `andi', `ori' and `xori' produce the
 * same value at any step.
 *
 * The other two constants are picked for which RULE their value selects:
 * 0xdeadbeef is too wide for the immediate field and goes through
 * `reg_cnstu_wide', which is also the only place in this corpus where lcc's
 * HEXADECIMAL spelling of an unsigned constant reaches poc/04-assembler; 0
 * goes through `reg_zerou' and becomes the zero register rather than any
 * instruction at all. `z' is stored and then tested so that a `reg_zerou'
 * emitting some other register changes the ANSWER -- comparing against a
 * constant zero that is never stored would leave the branch untaken either
 * way, and the rule would be pinned by nothing but its own template.
 *
 * The six comparisons are written the way that produces all six opcodes: lcc
 * emits the INVERTED test for the branch that skips the body, so `>' arrives
 * as LEU4 and `<=' as GTU4.
 *
 * uh() and uhook are in drivers/unsig.s and drivers/unsig.c. uhook is the same
 * function reached through a pointer, which is the only way C reaches the
 * INDIRECT CALLU4 rows -- ir/voidcall.c makes that argument for the I-typed
 * pair, and all four U-typed call rows are exercised here: used and discarded,
 * direct and indirect.
 */
extern unsigned uh(unsigned a, unsigned b);
extern unsigned (*uhook)(unsigned, unsigned);

unsigned wide(unsigned a, unsigned b)
{
    unsigned x;
    unsigned y;
    unsigned z;

    x = a / b;
    x = x + a % b;
    x = x + (a >> 3);
    x = x + (a << 1);
    x = x + (a >> b);
    x = x + (a << b);
    x = x * b;
    x = x - b;
    x = x & a;
    x = x | b;
    x = x ^ b;
    x = ~x;

    y = a % b;
    y = y & 3;
    y = y | 3;
    y = y ^ 5;
    y = y + (a & 0xdeadbeef);
    x = x + y;

    z = 0;

    if (a > b)
        x = x + 1;
    if (a <= b)
        x = x + 2;
    if (a < b)
        x = x + 4;
    if (a >= b)
        x = x + 8;
    if (a == b)
        x = x + 16;
    if (a != b)
        x = x + 32;
    if (z == 0)
        x = x + 64;
    uh(x, b);
    uhook(x, b);
    x = uhook(x, b);
    return uh(x, b);
}
