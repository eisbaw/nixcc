/* __udivsi3 and __umodsi3 with a DIVISOR whose top bit is set, which
 * ir/unsig.c does not have (task-051).
 *
 * The two cases divide different things. ir/unsig.c has an unsigned DIVIDEND
 * above 2^31, which is what tells __udivsi3 from __divsi3 -- a question about
 * the rule table. This file has an unsigned DIVISOR above 2^31, which is what
 * tells `bltu' from `blt' INSIDE __udivsi3 -- a question about the routine.
 * Neither case can answer the other's question: with a divisor of 9 the
 * routine's own comparison never sees a negative-looking operand, and with a
 * dividend of 0xfffffffe the rule table's choice is already settled by the
 * other file.
 *
 * THE COMBINING OPERATOR IS `^' AND IT WAS `+', which is worth a paragraph
 * because the change was forced by a measurement rather than chosen. With
 * `a / b + a % b' the signed-comparison mutation was NOT DETECTED: it moves
 * the quotient from 1 to 0xffffffff and the remainder from 0x7ffffffd to
 * 0x7fffffff, and modulo 2^32 those two errors cancel in the sum exactly.
 * `^' does not cancel them. A case whose two halves can trade error for error
 * is not testing two things, it is testing their sum.
 */
unsigned wrap(unsigned a, unsigned b)
{
    return (a / b) ^ (a % b);
}
