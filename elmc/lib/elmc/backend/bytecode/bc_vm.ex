defmodule Elmc.Backend.Bytecode.BcVm do
  @moduledoc false

  alias Elmc.Backend.Bytecode.{ProjectWriter, TierGate, TierMetrics}

  @spec enabled?(map()) :: boolean()
  def enabled?(opts) when is_map(opts) do
    Map.get(opts, :bc_vm_enabled, false) == true and
      ProjectWriter.selective_pebble_bytecode?(opts) and
      TierGate.eligible?(Map.get(opts, :bytecode_tier_metrics, %{}))
  end

  @spec disabled_reason(map()) :: String.t()
  def disabled_reason(opts) when is_map(opts) do
    cond do
      Map.get(opts, :bc_vm_enabled, false) != true ->
        "bc_vm_enabled is false (deferred until TierGate clears)"

      not ProjectWriter.selective_pebble_bytecode?(opts) ->
        "selective pebble bytecode is off"

      not TierGate.eligible?(Map.get(opts, :bytecode_tier_metrics, %{})) ->
        "TierGate metrics do not clear bytecode tier criteria"

      true ->
        "enabled"
    end
  end

  @spec metrics_from_out_dir(String.t(), keyword()) :: map()
  def metrics_from_out_dir(out_dir, opts \\ []) when is_binary(out_dir) do
    TierMetrics.from_out_dir(out_dir, opts)
  end

  @spec header_c() :: String.t()
  def header_c do
    """
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
    """
  end
end
