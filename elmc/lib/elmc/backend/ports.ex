defmodule Elmc.Backend.Ports do
  @moduledoc """
  Generates C headers for Ports callback ABI.
  """

  alias ElmEx.IR

  @spec write_port_headers(IR.t(), String.t()) :: :ok | {:error, term()}
  def write_port_headers(_ir, out_dir) do
    ports_dir = Path.join(out_dir, "ports")

    with :ok <- File.mkdir_p(ports_dir),
         :ok <- File.write(Path.join(ports_dir, "elmc_ports.h"), ports_header()),
         :ok <- File.write(Path.join(ports_dir, "elmc_ports.c"), ports_source()) do
      :ok
    end
  end

  @spec ports_header() :: String.t()
  defp ports_header do
    """
    #ifndef ELMC_PORTS_H
    #define ELMC_PORTS_H

    #include "../runtime/elmc_runtime.h"

    typedef struct {
      ElmcPortCallback callback;
      void *context;
    } ElmcIncomingRegistration;

    int register_incoming_port(const char *port_name, ElmcPortCallback callback, void *context);
    int send_outgoing_port(const char *port_name, ElmcValue *payload);
    void elmc_ports_reset(void);

    #endif
    """
  end

  @spec ports_source() :: String.t()
  defp ports_source do
    """
    #include "elmc_ports.h"
    #include <string.h>

    #define ELMC_MAX_PORTS 32

    typedef struct {
      const char *name;
      ElmcPortCallback callback;
      void *context;
    } ElmcPortSlot;

    static ElmcPortSlot ELMC_PORTS[ELMC_MAX_PORTS];
    static int ELMC_PORT_COUNT = 0;

    int register_incoming_port(const char *port_name, ElmcPortCallback callback, void *context) {
      if (!port_name || !callback) return -1;
      if (ELMC_PORT_COUNT >= ELMC_MAX_PORTS) return -2;
      ELMC_PORTS[ELMC_PORT_COUNT].name = port_name;
      ELMC_PORTS[ELMC_PORT_COUNT].callback = callback;
      ELMC_PORTS[ELMC_PORT_COUNT].context = context;
      ELMC_PORT_COUNT += 1;
      return 0;
    }

    int send_outgoing_port(const char *port_name, ElmcValue *payload) {
      if (!port_name) return -1;
      for (int i = 0; i < ELMC_PORT_COUNT; i++) {
        if (strcmp(port_name, ELMC_PORTS[i].name) == 0) {
          ELMC_PORTS[i].callback(payload, ELMC_PORTS[i].context);
          return 0;
        }
      }
      return -3;
    }

    void elmc_ports_reset(void) {
      ELMC_PORT_COUNT = 0;
    }
    """
  end
end
