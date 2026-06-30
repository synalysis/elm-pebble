defmodule Elmc.Backend.CCodegen.BuildArtifacts do
  @moduledoc false

  @spec cmake() :: String.t()
  def cmake do
    """
    cmake_minimum_required(VERSION 3.20)
    project(elmc_generated C)

    add_compile_options(-ffunction-sections -fdata-sections)
    add_link_options(-Wl,--gc-sections)

    add_library(elmc_runtime runtime/elmc_runtime.c)
    target_link_libraries(elmc_runtime PRIVATE m)
    add_library(elmc_ports ports/elmc_ports.c)
    add_library(elmc_generated c/elmc_generated.c)
    add_library(elmc_worker c/elmc_worker.c)
    add_library(elmc_pebble c/elmc_pebble.c)
    target_include_directories(elmc_runtime PUBLIC runtime)
    target_include_directories(elmc_ports PUBLIC ports runtime)
    target_include_directories(elmc_generated PUBLIC c ports runtime)
    target_include_directories(elmc_worker PUBLIC c ports runtime)
    target_include_directories(elmc_pebble PUBLIC c ports runtime)
    target_link_libraries(elmc_generated PRIVATE elmc_runtime elmc_ports)
    target_link_libraries(elmc_worker PRIVATE elmc_generated elmc_ports elmc_runtime)
    target_link_libraries(elmc_pebble PRIVATE elmc_worker elmc_generated elmc_ports elmc_runtime)

    add_executable(elmc_host c/host_harness.c)
    target_include_directories(elmc_host PRIVATE c ports runtime)
    target_link_libraries(elmc_host PRIVATE elmc_pebble elmc_worker elmc_generated elmc_ports elmc_runtime)
    """
  end

  @spec makefile() :: String.t()
  def makefile do
    """
    CC ?= cc
    CFLAGS ?= -std=c11 -Wall -Wextra -ffunction-sections -fdata-sections -Iruntime -Iports -Ic
    # Optional: CFLAGS += -DELMC_RC_TRACK=1 for host harness leak diagnostics
    LDFLAGS ?= -Wl,--gc-sections -lm
    SOURCES := runtime/elmc_runtime.c ports/elmc_ports.c c/elmc_generated.c c/elmc_worker.c c/elmc_pebble.c c/host_harness.c

    all: elmc_host

    elmc_host: $(SOURCES)
    \t$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o elmc_host

    clean:
    \trm -f elmc_host
    """
  end

  @spec host_harness() :: String.t()
  def host_harness do
    """
    #include "elmc_generated.h"
    #include <stdio.h>

    static void on_outgoing(ElmcValue *value, void *context) {
      (void)context;
      printf("port callback value=%lld\\n", (long long)elmc_as_int(value));
    }

    int main(void) {
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
        register_incoming_port("demo", on_outgoing, NULL);
        ElmcValue *payload = NULL;
        Rc = elmc_new_int(&payload, 7);
        CHECK_RC(Rc);
        send_outgoing_port("demo", payload);
        elmc_release(payload);
      CATCH_END
      return (int)Rc;
    }
    """
  end
end
