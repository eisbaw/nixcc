/* Calls: a nested call in an argument, a call whose result is discarded (the
 * case task-025 had to teach the backend), and a void function. */
extern int add(int, int);
extern void note(int);

int mix(int a, int b)
{
    int r;

    r = add(a, add(b, 1));
    add(r, r);
    note(r);
    return r;
}
