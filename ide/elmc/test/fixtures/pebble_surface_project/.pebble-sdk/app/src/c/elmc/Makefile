CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Iruntime -Iports -Ic
SOURCES := runtime/elmc_runtime.c ports/elmc_ports.c c/elmc_generated.c c/elmc_worker.c c/elmc_pebble.c c/host_harness.c

all: elmc_host

elmc_host: $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) -o elmc_host

clean:
	rm -f elmc_host
