#ifndef TC_REGION_STATE_H
#define TC_REGION_STATE_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "layout.h"

/* Owned, non-executable staging memory. One outstanding allocation per
 * transaction. No address aliasing, debugger protocol or permission changes. */
typedef enum { TC_REGION_EMPTY, TC_REGION_STAGING, TC_REGION_READY, TC_REGION_RETIRED } TCRegionPhase;
typedef struct {
    unsigned char *staging;
    size_t capacity, size, written;
    TCRegionPhase phase;
} TCRegionState;

static inline int tcRegionBegin(TCRegionState *s, unsigned char *storage, size_t capacity, size_t count) {
    if (!s || s->phase != TC_REGION_EMPTY || !storage || !tcJITContains(capacity,0,count)) return 0;
    memset(storage,0,count);
    *s=(TCRegionState){storage,capacity,count,0,TC_REGION_STAGING};
    return 1;
}
static inline int tcRegionAppend(TCRegionState *s, const void *bytes, size_t n) {
    if (!s || s->phase != TC_REGION_STAGING || !bytes || !s->staging ||
        !tcJITContains(s->size,s->written,n)) return 0;
    memcpy(s->staging+s->written,bytes,n);
    s->written+=n;
    return 1;
}
static inline int tcRegionComplete(TCRegionState *s) {
    if (!s || s->phase != TC_REGION_STAGING || !s->staging || s->written != s->size) return 0;
    s->phase=TC_REGION_READY;
    return 1;
}
static inline void tcRegionRetire(TCRegionState *s) {
    if (!s || s->phase == TC_REGION_RETIRED) return;
    if (s->staging && s->size <= s->capacity) memset(s->staging,0,s->size);
    *s=(TCRegionState){0};
    s->phase=TC_REGION_RETIRED;
}
#endif
