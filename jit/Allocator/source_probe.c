/* Source-level feasibility only. Uses Apple's documented callback mechanism.
 * Not linked into the game or diagnostic host. No signing/entitlement changes.
 * The writer only accepts the fixed, benign synthetic instruction sequence.
 * There is deliberately no API to accept external executable bytes, attach a
 * debugger, change arbitrary permissions, or call generated instructions.
 */
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <libkern/OSCacheControl.h>
#include "layout.h"
#include "region_state.h"

#if !defined(__aarch64__)
#error ARM64-only source probe
#endif

typedef struct {
    uint8_t *region;
    size_t capacity;
    size_t offset;
    const TCRegionState *staged;
} TCJITProbeContext;

/* mov w0, #42; ret (synthetic constant-return function, not game code). */
static const uint32_t tcFixedCode[] = { 0x52800540u, 0xd65f03c0u };

static int tcFixedWriter(void *opaque) {
    TCJITProbeContext *ctx = opaque;
    if (!ctx || !ctx->region || !ctx->staged ||
        ctx->staged->phase != TC_REGION_READY ||
        ctx->staged->size != sizeof(tcFixedCode) || ctx->staged->written != sizeof(tcFixedCode) ||
        !ctx->staged->staging || ctx->staged->capacity < sizeof(tcFixedCode) ||
        memcmp(ctx->staged->staging,tcFixedCode,sizeof(tcFixedCode)) ||
        (ctx->offset & 3u) ||
        !tcJITContains(ctx->capacity, ctx->offset, sizeof(tcFixedCode))) return EINVAL;
    memcpy(ctx->region + ctx->offset, ctx->staged->staging, sizeof(tcFixedCode));
    return 0;
}

PTHREAD_JIT_WRITE_ALLOW_CALLBACKS_NP(tcFixedWriter);

/* Compile-only proof of API linkage. Calling this on a device requires
 * genuine, applicable JIT authorization and a permitted callback allowlist.
 * This source is not included in any runnable IPA. */
int tcSourceAllocatorProbe(void) {
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) return EINVAL;
    size_t capacity = (size_t)page;
    TCJITLayout layout = {capacity, 0};
    size_t offset = 0;
    if (!tcJITReserve(&layout, sizeof(tcFixedCode), 4, &offset)) return EINVAL;
    unsigned char staging[sizeof(tcFixedCode)];
    TCRegionState staged={0};
    if (!tcRegionBegin(&staged,staging,sizeof(staging),sizeof(tcFixedCode)) ||
        !tcRegionAppend(&staged,tcFixedCode,sizeof(tcFixedCode)) ||
        !tcRegionComplete(&staged)) return EINVAL;
    void *region = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (region == MAP_FAILED) {
        int failure=errno;tcRegionRetire(&staged);return failure;
    }
    TCJITProbeContext context = {region, capacity, offset, &staged};
    int result = pthread_jit_write_with_callback_np(tcFixedWriter, &context);
    if (result == 0) sys_icache_invalidate((uint8_t *)region + offset, sizeof(tcFixedCode));
    if (munmap(region, capacity) != 0 && result == 0) result = errno;
    tcRegionRetire(&staged);
    return result;
}
