#ifndef TC_ARM64_SUBSET_H
#define TC_ARM64_SUBSET_H
#include <stddef.h>
#include <stdint.h>

typedef enum { TC_OK, TC_ARGUMENT, TC_UNSUPPORTED, TC_BOUNDS, TC_BUDGET } TCStatus;
typedef struct { uint64_t x[31]; uint8_t nzcv; } TCRegisters;
/* Instruction words are immutable data. Memory is an isolated little-endian
 * guest buffer, never a host address. Failure leaves partial guest state;
 * callers must discard it. No host callbacks, syscalls or executable pages. */
TCStatus tc_interpret(const uint32_t *words, size_t count, TCRegisters *regs,
                      uint8_t *memory, size_t memory_size, size_t budget);
#endif
