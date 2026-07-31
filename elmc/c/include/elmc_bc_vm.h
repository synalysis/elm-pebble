#ifndef ELMC_BC_VM_H
#define ELMC_BC_VM_H

#include "elmc_runtime.h"

#ifndef ELMC_BC_VM_ENABLED
#define ELMC_BC_VM_ENABLED 0
#endif

typedef struct {
  const uint8_t *code;
  uint32_t code_len;
  uint16_t locals;
} ElmcBcSection;

#if ELMC_BC_VM_ENABLED
RC elmc_bc_call(ElmcValue **out, uint16_t section_id, ElmcValue **args, int argc);
#else
static inline RC elmc_bc_call(ElmcValue **out, uint16_t section_id, ElmcValue **args, int argc) {
  (void)section_id;
  (void)args;
  (void)argc;
  if (out) *out = NULL;
  return RC_ERR_UNSUPPORTED;
}
#endif

#endif
