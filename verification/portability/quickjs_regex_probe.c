/* Experimental standalone libregexp port. Not a production backend or NIF. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libregexp.h"

typedef struct {
    uintptr_t stack_base;
    unsigned ticks, budget;
    int failed;
} Scope;

int lre_check_stack_overflow(void *opaque, size_t requested) {
    Scope *scope = opaque;
    char local;
    uintptr_t here = (uintptr_t)&local;
    size_t used = here > scope->stack_base ? here - scope->stack_base : scope->stack_base - here;
    if (used + requested > 512 * 1024) { scope->failed = 1; return 1; }
    return 0;
}
int lre_check_timeout(void *opaque) {
    Scope *scope = opaque;
    if (++scope->ticks > scope->budget) { scope->failed = 1; return 1; }
    return 0;
}
void *lre_realloc(void *opaque, void *ptr, size_t size) {
    Scope *scope = opaque;
    if (!size) { free(ptr); return NULL; }
    void *next = realloc(ptr, size);
    if (!next) scope->failed = 1;
    return next;
}
static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}
/* Results: invalid syntax=0, valid/no match=1, valid/match=2, operational=3. */
static uint8_t run(const uint8_t *request, uint32_t length) {
    if (length < 12) return 3;
    uint32_t budget = u32(request), plen = u32(request + 4), units = u32(request + 8);
    if ((uint64_t)plen + (uint64_t)units * 2 + 12 != length) return 3;
    char local;
    Scope scope = {(uintptr_t)&local, 0, budget, 0};
    char *pattern = malloc((size_t)plen + 1);
    uint16_t *text = calloc((size_t)units + 1, sizeof(*text));
    if (!pattern || !text) { free(pattern); free(text); return 3; }
    memcpy(pattern, request + 12, plen); pattern[plen] = 0;
    const uint8_t *input = request + 12 + plen;
    for (uint32_t i = 0; i < units; i++) text[i] = input[2*i] | (uint16_t)input[2*i+1] << 8;
    int bytecode_length;
    char error[256];
    uint8_t *bytecode = lre_compile(&bytecode_length, error, sizeof(error), pattern,
                                  plen, LRE_FLAG_UNICODE, &scope);
    uint8_t answer;
    if (!bytecode) answer = scope.failed ? 3 : 0;
    else {
        // The 2026 API adds registers beyond the visible capture slots.
#ifdef PROBE_NEW_REGISTERS
        size_t count = (size_t)lre_get_alloc_count(bytecode);
#else
        size_t count = (size_t)lre_get_capture_count(bytecode) * 2;
#endif
        uint8_t **captures = calloc(count, sizeof(*captures));
        if (!captures) answer = 3;
        else {
            int result = lre_exec(captures, bytecode, (uint8_t *)text, 0, (int)units, 1, &scope);
            answer = result < 0 ? 3 : result ? 2 : 1;
        }
        free(captures); free(bytecode);
    }
    free(pattern); free(text); return answer;
}
int main(void) {
    uint8_t header[4];
    while (fread(header, 1, 4, stdin) == 4) {
        uint32_t length = u32(header);
        if (length > 16 * 1024 * 1024) return 2;
        uint8_t *request = malloc(length ? length : 1);
        if (!request || fread(request, 1, length, stdin) != length) { free(request); return 2; }
        uint8_t reply[5] = {0, 0, 0, 1, run(request, length)};
        free(request);
        if (fwrite(reply, 1, 5, stdout) != 5 || fflush(stdout)) return 2;
    }
    return ferror(stdin) ? 2 : 0;
}
