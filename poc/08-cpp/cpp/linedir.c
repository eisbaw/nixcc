/* #line, with and without a file name, and the `# n "file"' spelling that
   lcc's input.c resynch() reads. Nothing about the TOKENS changes, which is
   why linemarkers are checked against rcc's diagnostics instead. */
int before = 1;
#line 100
int after_number_only = 2;
#line 200 "renamed.c"
int after_number_and_file = 3;
# 300 "again.c"
int after_linemarker = 4;
