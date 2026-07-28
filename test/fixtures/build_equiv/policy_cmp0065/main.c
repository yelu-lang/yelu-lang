/* CMP0065 OLD adds -rdynamic (exports symbols to the exe's dynamic table);
   NEW does not (unless ENABLE_EXPORTS). Where the toolchain honors it, the
   two states differ in `nm -D app`. */
int exported_helper(void) { return 42; }
int main(void) { return exported_helper() - 42; }
