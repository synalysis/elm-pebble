defmodule Ide.PebbleToolchain.Types do
  @moduledoc false

  alias Ide.CompanionProtocol.WireSchema

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
          | {:capabilities, [String.t()] | String.t()}
        ]

  @type toolchain_error ::
          atom()
          | String.t()
          | Exception.t()
          | {:workspace_root_not_found, String.t()}
          | {:build_app_root_failed, File.posix()}
          | {:copy_file_failed, String.t(), File.posix()}
          | {:pebble_build_failed, command_result()}
          | {:pebble_wipe_failed, command_result()}
          | {:pebble_emulator_slots_unavailable, String.t()}
          | {:unsupported_emulator_control, term()}
          | {:package_path_not_found, String.t()}
          | {:package_path_not_pbw, String.t()}
          | {:latest_pbw_not_found, String.t()}
          | {:elmc_compile_failed, term()}
          | {:compiler_exception, term(), term()}
          | {:companion_protocol_schema_failed, term()}
          | {:runtime_generation_failed, term()}
          | tuple()

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
  @type elmc_compile_result :: %{
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type emulator_control_params :: %{
          required(String.t()) => wire_input(),
          optional(String.t()) => wire_input()
        }

  @type core_ir_expr :: ElmEx.CoreIR.Types.Expr.t() | ElmEx.CoreIR.Types.Expr.wire_expr()
  @type app_message_keys :: WireSchema.key_ids()
  @type preferences_schema :: Ide.PebblePreferences.schema() | nil
end
