#ifndef ELMC_WASM_RUNTIME_H
#define ELMC_WASM_RUNTIME_H

#include <stdint.h>

typedef int32_t RC;
typedef int32_t ElmcValue;

#define RC_SUCCESS 0
#define RC_ERR_OUT_OF_MEMORY 1

RC elmc_wasm_runtime_stub(void);

#endif
