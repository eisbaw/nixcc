/* Union types: the same storage read through two members, which is the only
 * thing a union is for and the only thing that can tell a union apart from a
 * struct in a listing.
 *
 * `u.i = 258' then `u.b[0]' and `u.b[1]' is the overlap, at byte resolution:
 * 258 is 0x102, so the two bytes differ and reading the wrong one changes the
 * answer. A union laid out like a struct would put `b' after `i' and both
 * reads would be of uninitialised storage -- correct-looking code and a
 * different program, which is why the offsets and not just the size are what
 * this file pins.
 *
 * `union W' holds a single `char' and is still FOUR bytes, because
 * symbolicIR's structmetric aligns every aggregate to four. The size of a
 * one-char union is the cheapest place that rule is visible.
 */
union U {
    int   i;
    char  b[4];
    short h;
};

union W {
    char c;
};

int through(union U *u)
{
    u->i = 7;
    u->b[2] = 1;
    return u->i + u->h + u->b[0];
}

int overlap(void)
{
    union U u;
    union W w;
    union U m[2];

    u.i = 258;
    w.c = 3;
    m[1].h = 9;
    return u.b[0] + u.b[1] + w.c + m[1].h
        + sizeof(union U) + sizeof(union W) + sizeof m;
}
