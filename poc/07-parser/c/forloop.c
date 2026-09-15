/* A for loop, whose four labels and whose two `definept' points make the code
 * list shape different from a while loop's even though the C means the same. */
int total(int n)
{
    int i;
    int s;

    s = 0;
    for (i = 0; i < n; i++)
        s = s + i * i;
    return s;
}

/* A for loop whose bounds are both constants, which is the case stmt.c's
 * foldcond() decides at compile time: the loop is known to run at least once,
 * so the branch over the body and the label it jumps to are not emitted at
 * all. Without this function nothing in the corpus tells a frontend that
 * skipped foldcond entirely from one that implemented it. */
int fixed(int a)
{
    int i;
    int s;

    s = 0;
    for (i = 0; i < 10; i++)
        s = s + a;
    return s;
}
