struct pt { int x; int y; };

int dist(struct pt *p)
{
    int d;

    d = p->y - p->x;
    p->x = d;
    return d;
}
