#include <stdio.h>
const char *greet(void);
int greet_len(void);
int main(void) { printf("%s (%d)\n", greet(), greet_len()); return 0; }
