/* A void function with no return value and no statements after the last one,
 * so compound() supplies the fall-through RET itself, and an empty statement. */
void nothing(int a)
{
    int x;

    x = a;
    ;
}
