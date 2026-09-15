/* Arrays belong to slice 3 (task-029) and subscripting one is refused. Their
 * TYPE is reachable today, though, and it does not print the way a recursive
 * formatter would: lcc collapses the dimensions of a nested array into one
 * list and names the innermost element type, so a two-dimensional array is
 * `array 2,3 of int' and not `array 2 of array 3 of int'. This file is here
 * because that divergence was live until it was diffed.
 *
 * Declaring an array also marks the symbol `addressed', which takes it out of
 * the running for a register however often it is read -- another thing only
 * the listing shows.
 */
int sizes(void)
{
    int one[3];
    int two[2][3];
    int used;

    used = sizeof one + sizeof two;
    return used;
}
