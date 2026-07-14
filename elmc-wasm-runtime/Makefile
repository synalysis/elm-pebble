RUNTIME_DIR := runtime
HOST_DIR := host
OUT := $(RUNTIME_DIR)/elmc_runtime.wasm

CLANG ?= clang
WAT2WASM ?= wat2wasm

.PHONY: all runtime host clean

all: runtime host

runtime: $(OUT)

$(OUT): $(RUNTIME_DIR)/elmc_runtime.c $(RUNTIME_DIR)/elmc_runtime.h
	$(CLANG) --target=wasm32-unknown-unknown -O2 -nostdlib \
		-I$(RUNTIME_DIR) -c $(RUNTIME_DIR)/elmc_runtime.c -o $(RUNTIME_DIR)/elmc_runtime.o
	# Link step is project-specific once symbols are pruned from manifest imports.

host:
	@test -f $(HOST_DIR)/loader.js

clean:
	rm -f $(RUNTIME_DIR)/*.o $(OUT)
