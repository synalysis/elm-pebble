defmodule Ide.PebbleToolchain.Types do
  @moduledoc false

  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias Ide.CompanionProtocol.WireSchema

  @type cli_diagnostic :: Elmc.Types.cli_diagnostic()

  @type project_slug :: String.t()
  @type opts :: pebble_opts()
  @type wire_scalar :: String.t() | integer() | float() | boolean() | nil
  @type wire_input :: wire_scalar() | [wire_input()] | %{optional(String.t()) => wire_input()}

  @type command_result :: %{
          required(:status) => :ok | :error,
          required(:command) => String.t(),
          required(:output) => String.t(),
          required(:exit_code) => integer(),
          required(:cwd) => String.t()
        }

  @type package_result :: %{
          required(:status) => :ok | :error,
          required(:artifact_path) => String.t(),
          required(:build_result) => command_result(),
          required(:app_root) => String.t(),
          required(:has_phone_companion) => boolean(),
          required(:has_companion_preferences) => boolean()
        }

  @type pebble_opts :: [
          {:app_root, String.t()}
          | {:cwd, String.t()}
          | {:env, [{String.t(), String.t()}]}
          | {:workspace_root, String.t()}
          | {:source_roots, [String.t()] | nil}
          | {:target_type, String.t()}
          | {:project_name, String.t()}
          | {:target_platforms, [String.t()]}
          | {:emulator_target, String.t()}
          | {:package_path, String.t()}
          | {:is_published, boolean()}
          | {:release_notes, String.t()}
          | {:description, String.t()}
          | {:version, String.t()}
          | {:screenshots, [String.t()]}
          | {:force, boolean()}
          | {:timeout_seconds, pos_integer()}
          | {:emulator_storage_logs, boolean()}
          | {:emulator_agent_probes, boolean()}
          | {:emulator_heap_log, boolean()}
          | {:emulator_debug_logs, boolean()}
          | {:prod, boolean()}
          | {:debug_usage_policy, :error | :warn | :warning}
          | {:capabilities, [String.t()] | String.t()}
        ]

  @typedoc "Local mirror of `Ide.CompanionProtocolGenerator.generator_error/0`."
  @type companion_protocol_generator_error ::
          {:missing_union, String.t()}
          | {:wire_schema_too_large, WireSchema.wire_schema_too_large_detail()}
          | File.posix()

  @typedoc "Local mirror of `Elmx.Types.emit_error/0` plus other in-memory compile failures."
  @type elmx_emit_error ::
          {:unsupported_op, atom(), String.t()}
          | {:emit_failed, String.t()}

  @type file_posix :: File.posix()

  @type compiler_catch_scalar :: atom() | String.t() | integer() | float() | boolean() | nil

  @type compiler_catch_reason ::
          compiler_catch_scalar()
          | [compiler_catch_reason()]
          | %{optional(String.t()) => compiler_catch_reason()}

  @type compiler_exception ::
          {:compiler_exception, module(), String.t()}
          | {:compiler_exception, atom(), compiler_catch_reason()}

  @type elmc_compile_result :: Elmc.Types.compile_result()

  @typedoc "Local mirror of ElmEx bridge/load failures surfaced through `Elmc.compile/2`."
  @type elm_bridge_error :: %{
          optional(:kind) => :config_error | :parse_error | :elm_check_failed | atom(),
          optional(:reason) => atom() | String.t(),
          optional(:path) => String.t(),
          optional(:line) => integer() | String.t() | nil,
          optional(:diagnostics) => [cli_diagnostic()],
          optional(:raw) => String.t(),
          optional(String.t()) => wire_input()
        }

  @type runtime_reprune_failure :: file_posix() | :unbalanced_braces

  @type elmc_failure_reason ::
          Elmc.Types.compile_error()
          | file_posix()
          | atom()
          | String.t()
          | Exception.t()

  @type phone_companion_elm_make_result :: %{
          required(:command) => String.t(),
          required(:output) => String.t(),
          required(:exit_code) => integer(),
          required(:cwd) => String.t()
        }

  @type toolchain_error_atom ::
          :compile_project_root_not_found
          | :elm_compiler_not_found
          | :external_emulator_disabled
          | :invalid_button
          | :invalid_button_action
          | :invalid_compass_heading
          | :invalid_percent
          | :invalid_set_time
          | :invalid_tap_direction
          | :not_found
          | :package_path_required
          | :pbw_artifact_not_found
          | :pebble_cli_not_found
          | :publish_app_root_required
          | :template_app_root_not_found
          | :timeout
          | :timeout_utility_not_found
          | :workspace_root_required
          | file_posix()

  @type toolchain_error ::
          toolchain_error_atom()
          | String.t()
          | Exception.t()
          | {:workspace_root_not_found, String.t()}
          | {:build_app_root_failed, file_posix()}
          | {:copy_file_failed, String.t(), file_posix()}
          | {:pebble_build_failed, command_result()}
          | {:pebble_wipe_failed, command_result()}
          | {:forbidden_build_warnings, [String.t()], command_result()}
          | {:pebble_emulator_slots_unavailable, String.t()}
          | {:unsupported_emulator_control, wire_input() | nil}
          | {:package_path_not_found, String.t()}
          | {:package_path_not_pbw, String.t()}
          | {:publish_app_root_not_found, String.t()}
          | {:list_build_dir_failed, file_posix()}
          | {:bitmap_resource_stage_failed, String.t(), file_posix()}
          | {:elmc_compile_failed, elmc_failure_reason()}
          | {:companion_protocol_schema_failed, companion_protocol_generator_error()}
          | {:companion_protocol_generation_failed, companion_protocol_generator_error()}
          | {:companion_protocol_elm_generation_failed, companion_protocol_generator_error()}
          | {:read_companion_index_template_failed, file_posix()}
          | {:phone_companion_elm_make_failed, phone_companion_elm_make_result()}
          | {:runtime_reprune_failed, runtime_reprune_failure()}
          | {:invalid_emulator_target, String.t()}

  @type pebble_package :: %{optional(String.t()) => pebble_package_value()}
  @type pebble_package_value ::
          String.t()
          | integer()
          | boolean()
          | [pebble_package_value()]
          | pebble_package()
          | nil

  @type pebble_media_entry :: %{
          optional(String.t()) => String.t() | integer() | boolean() | [String.t()]
        }

  @type elmc_compile_opts :: Elmc.Types.compile_options()

  @typedoc "Partial elmc options merged into watch compile opts (local mirror of `Elmc.Types.compile_options/0`)."
  @type elmc_extra_opts :: %{
          optional(:entry_module) => String.t(),
          optional(:out_dir) => String.t() | nil,
          optional(:runtime_dir) => String.t(),
          optional(:strip_dead_code) => boolean(),
          optional(:prune_runtime) => boolean(),
          optional(:prune_native_wrappers) => boolean(),
          optional(:direct_render_only) => boolean(),
          optional(:prune_direct_generic) => boolean(),
          optional(:pebble_int32) => boolean(),
          optional(:linked_binary_map) => String.t(),
          optional(:prod) => boolean(),
          optional(:plan_ir_mode) => :off | :shadow | :primary,
          optional(:plan_ir_strict) => boolean(),
          optional(:debug_usage_policy) => :error | :warn | :warning,
          optional(:codegen_profile) => :default | :balanced | :size,
          optional(:optimize_for_size) => boolean()
        }

  @type watch_compile_opts :: Elmc.Types.compile_options()

  @type emulator_control_params :: %{
          required(String.t()) => wire_input(),
          optional(String.t()) => wire_input()
        }

  @type core_ir :: CoreIRTypes.wire_core_ir() | nil
  @type core_ir_expr :: CoreIRTypes.expr() | CoreIRTypes.Expr.wire_expr()
  @type app_message_keys :: WireSchema.key_ids()
  @type preferences_schema :: Ide.PebblePreferences.schema() | nil
end
