#ifndef TC_JIT_LAYOUT_H
#define TC_JIT_LAYOUT_H
#include <stddef.h>
#include <stdint.h>

/* Source-level allocator layout. No executable memory or protection changes. */
typedef struct {
    size_t capacity;
    size_t used;
} TCJITLayout;

static inline int tcJITReserve(TCJITLayout *layout, size_t count, size_t alignment, size_t *offset) {
    if (!layout || !offset || !count || !alignment || (alignment & (alignment - 1)) ||
        layout->used > layout->capacity || layout->used > SIZE_MAX - (alignment - 1)) return 0;
    size_t start = (layout->used + alignment - 1) & ~(alignment - 1);
    if (start > layout->capacity || count > layout->capacity - start) return 0;
    *offset = start;
    layout->used = start + count;
    return 1;
}
static inline int tcJITContains(size_t capacity, size_t offset, size_t count) {
    return count != 0 && offset <= capacity && count <= capacity - offset;
}
#endif
