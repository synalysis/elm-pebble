defmodule Elmc.Types do
  @moduledoc """
  Shared types used across elmc packages.
  """

  @type file_error :: File.posix()

  @type module_name :: String.t()
  @type function_name :: String.t()

  @type debug_usage_policy :: :error | :warn | :warning

  @type plan_ir_mode :: :off | :shadow | :primary
  @type codegen_profile :: :default | :balanced | :size
  @type plan_emit_mode :: :goto | :state_switch

  @type compile_options :: %{
          optional(:entry_module) => module_name(),
          optional(:out_dir) => String.t() | nil,
          optional(:runtime_dir) => String.t(),
          optional(:strip_dead_code) => boolean(),
          optional(:prune_runtime) => boolean(),
          optional(:prune_native_wrappers) => boolean(),
          optional(:direct_render_only) => boolean(),
          optional(:prune_direct_generic) => boolean(),
          optional(:stream_view_fallback) => boolean(),
          optional(:pebble_int32) => boolean(),
          optional(:linked_binary_map) => String.t(),
          optional(:prod) => boolean(),
          optional(:plan_ir_mode) => plan_ir_mode(),
          optional(:plan_ir_strict) => boolean(),
          optional(:codegen_profile) => codegen_profile(),
          optional(:plan_emit) => plan_emit_mode(),
          optional(:enum_tag_peel) => boolean(),
          optional(:fusion_supersede_native) => boolean(),
          optional(:size_mod_by_fast) => boolean(),
          optional(:size_native_compare) => boolean(),
          optional(:size_prune_capabilities) => boolean(),
          optional(:size_aggressive_direct_render) => boolean(),
          optional(:debug_usage_policy) => debug_usage_policy()
        }
end
