#include <stdlib.h>
#include <time.h>

#define UNSAFE_EXIT 144
//#define nondet_signed_int __VERIFIER_nondet_signed_int

//#define __VERIFIER_assume(cond) do { if (!(cond)) __builtin_unreachable(); } while (0)
#define __CPROVER_assume(cond) do { if (!(cond)) __builtin_unreachable(); } while (0)

void __VERIFIER_error() { exit(UNSAFE_EXIT); }
int __VERIFIER_nondet_int() { srand(time(NULL)); return rand(); }
unsigned int __VERIFIER_nondet_unsignedint() { srand(time(NULL)); return (unsigned int) rand(); }
unsigned int __VERIFIER_nondet_uint() { srand(time(NULL)); return (unsigned int) rand(); }
signed int __VERIFIER_nondet_signed_int() { srand(time(NULL)); return (signed int) rand(); }
int nondet_signed_int() { srand(time(NULL)); return (signed int) rand(); }
void __VERIFIER_assume(int cond) { do { if (!(cond)) __builtin_unreachable(); } while (0);}
