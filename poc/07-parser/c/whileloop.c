/* A while loop with break and continue, so all three of the labels
 * whilestmt() allocates are exercised, and refinc's x10 weighting inside the
 * loop decides which locals become registers. */
int count(int n)
{
    int i;
    int s;

    i = 0;
    s = 0;
    while (i < n) {
        i = i + 1;
        if (i == 3) continue;
        if (i == 7) break;
        s = s + i;
    }
    return s;
}
