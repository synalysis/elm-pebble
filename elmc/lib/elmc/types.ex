defmodule Elmc.Types do
  @moduledoc """
  Shared types used across elmc packages.
  """

  alias ElmEx.Frontend.Project, as: FrontendProject
  alias ElmEx.IR
  alias ElmEx.Types, as: ElmExTypes

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
          optional(:debug_usage_policy) => debug_usage_policy(),
          optional(:targets) => [:c | :wasm],
          optional(:target) => String.t() | :c | :wasm,
          optional(:web) => boolean(),
          optional(:wasm_strict) => boolean(),
          optional(:wasm_binary) => boolean()
        }

  @type cli_diagnostic :: %{
          optional(:severity) => String.t(),
          optional(:message) => String.t(),
          optional(:source) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:line) => integer() | nil,
          optional(:column) => integer() | nil,
          optional(:warning_type) => atom() | String.t() | nil,
          optional(:warning_code) => atom() | String.t() | nil,
          optional(:warning_constructor) => String.t() | nil,
          optional(:warning_expected_kind) => atom() | String.t() | nil,
          optional(:warning_has_arg_pattern) => boolean() | nil,
          optional(String.t()) => String.t() | integer() | boolean() | nil
        }

  @type coverage_stat :: integer() | float() | boolean() | String.t() | nil

  @type coverage_bucket :: %{
          optional(String.t()) => coverage_stat() | coverage_bucket(),
          optional(atom()) => coverage_stat()
        }

  @type plan_coverage :: %{
          optional(String.t()) => coverage_bucket(),
          optional(atom()) => coverage_stat()
        }

  @type plan_toolchain :: %{
          optional(:mode) => :off | :shadow | :primary | String.t(),
          optional(:strict) => boolean(),
          optional(String.t()) => coverage_stat(),
          optional(atom()) => coverage_stat()
        }

  @type bytecode_function_row :: %{
          required(:module) => String.t(),
          required(:name) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:params) => [String.t()]
        }

  @type bytecode_skipped_row :: %{
          optional(:module) => String.t() | nil,
          optional(:name) => String.t() | nil,
          optional(:reason) => atom() | String.t() | nil
        }

  @type bytecode_summary_available :: %{
          required(:available) => true,
          optional(:contract) => String.t() | nil,
          optional(:version) => String.t() | nil,
          optional(:manifest_path) => String.t(),
          optional(:function_count) => non_neg_integer(),
          optional(:skipped_count) => non_neg_integer(),
          optional(:pruned_count) => non_neg_integer(),
          optional(:plan_toolchain) => plan_toolchain() | nil,
          optional(:plan_coverage) => plan_coverage() | nil,
          optional(:functions) => [bytecode_function_row()],
          optional(:skipped) => [bytecode_skipped_row()]
        }

  @type bytecode_summary_unavailable :: %{
          required(:available) => false,
          optional(:reason) => String.t()
        }

  @type bytecode_summary :: bytecode_summary_available() | bytecode_summary_unavailable()

  @type compiler_catch_scalar :: atom() | String.t() | integer() | float() | boolean() | nil

  @type compiler_catch_reason ::
          compiler_catch_scalar()
          | [compiler_catch_reason()]
          | %{optional(String.t()) => compiler_catch_reason()}

  @type frontend_config_error :: %{
          required(:kind) => :config_error,
          required(:reason) => :missing_elm_json | File.posix() | Jason.DecodeError.t(),
          optional(:path) => String.t()
        }

  @type frontend_parse_error :: %{
          required(:kind) => :parse_error,
          required(:path) => String.t(),
          optional(:line) => integer() | String.t() | nil,
          optional(:reason) => ElmExTypes.parse_reason()
        }

  @type frontend_elm_check_failed :: %{
          required(:kind) => :elm_check_failed,
          required(:diagnostics) => [cli_diagnostic()],
          required(:raw) => String.t()
        }

  @type frontend_bridge_error ::
          frontend_config_error()
          | frontend_parse_error()
          | frontend_elm_check_failed()
          | %{
              optional(atom()) => String.t() | integer() | boolean() | nil,
              optional(String.t()) => String.t() | integer() | boolean() | nil
            }

  @type compile_error ::
          frontend_bridge_error()
          | {:compile_diagnostics, [cli_diagnostic()]}
          | {:compiler_exception, module(), String.t()}
          | {:compiler_exception, atom(), compiler_catch_reason()}

  @type wasm_summary_available :: %{
          required(:available) => true,
          optional(:contract) => String.t() | nil,
          optional(:version) => integer() | nil,
          optional(:manifest_path) => String.t(),
          optional(:wat_path) => String.t() | nil,
          optional(:function_count) => non_neg_integer(),
          optional(:skipped_count) => non_neg_integer(),
          optional(:pruned_count) => non_neg_integer(),
          optional(:imports) => [String.t()],
          optional(:plan_toolchain) => plan_toolchain() | nil,
          optional(:plan_coverage) => plan_coverage() | nil,
          optional(:functions) => [map()],
          optional(:skipped) => [map()]
        }

  @type wasm_summary_unavailable :: %{
          required(:available) => false,
          optional(:reason) => String.t()
        }

  @type wasm_summary :: wasm_summary_available() | wasm_summary_unavailable()

  @type compile_result :: %{
          required(:project) => FrontendProject.t(),
          required(:ir) => IR.t(),
          optional(:debug_usage_diagnostics) => [cli_diagnostic()],
          optional(:layout_coercion_diagnostics) => [cli_diagnostic()],
          optional(:blocking_diagnostics) => [cli_diagnostic()],
          optional(:informational_diagnostics) => [cli_diagnostic()],
          optional(:plan_coverage) => plan_coverage() | nil,
          optional(:plan_toolchain) => plan_toolchain() | nil,
          optional(:elmc_bytecode_summary) => bytecode_summary(),
          optional(:elmc_wasm_summary) => wasm_summary()
        }

  @type object_text_source_row :: %{
          required(String.t()) => String.t() | non_neg_integer()
        }

  @type object_text_estimate_unavailable :: %{
          required(String.t()) => boolean() | String.t()
        }

  @type object_text_estimate_available :: %{
          required(String.t()) => boolean() | non_neg_integer() | nil | [object_text_source_row()],
          required(:available) => true,
          required(:elmc_app_text) => non_neg_integer(),
          required(:elmc_stack_text) => non_neg_integer(),
          optional(:generated_text) => non_neg_integer() | nil,
          required(:sources) => [object_text_source_row()]
        }

  @type object_text_estimate ::
          object_text_estimate_unavailable() | object_text_estimate_available()
end
