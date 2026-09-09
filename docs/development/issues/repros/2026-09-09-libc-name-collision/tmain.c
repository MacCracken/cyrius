#include <stdio.h>
extern void _cyrius_init(void); extern long alloc_init(void); extern long probe(void);
int main(void){ _cyrius_init(); alloc_init(); printf("probe() = %ld  (Cyrius expects 1)\n", probe()); return 0; }
