CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -ffunction-sections -fdata-sections -Iruntime -Iports -Ic
# Optional: CFLAGS += -DELMC_RC_TRACK=1 for host harness leak diagnostics
LDFLAGS ?= -Wl,--gc-sections -lm
SOURCES := runtime/elmc_runtime.c ports/elmc_ports.c c/elmc_generated.c c/elmc_worker.c c/elmc_pebble.c c/host_harness.c

all: elmc_host

elmc_host: $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o elmc_host

clean:
	rm -f elmc_host
