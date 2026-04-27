CC ?= cc
CJSON_DIR := cjson
CFLAGS ?= -std=c11 -Wall -Wextra -Iruntime -Iports -Ic -I$(CJSON_DIR) -DELMC_USE_CJSON=1
SOURCES := runtime/elmc_runtime.c ports/elmc_ports.c c/elmc_generated.c c/elmc_worker.c c/elmc_pebble.c c/host_harness.c $(CJSON_DIR)/cJSON.c

all: elmc_host

elmc_host: $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) -o elmc_host

clean:
	rm -f elmc_host
