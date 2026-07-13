defmodule Ide.Test.TemplateElmxElmcParity.Types do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Test.TemplateElmxElmcParity.ElmcHostHarness

  @type wire_json_scalar :: String.t() | integer() | float() | boolean() | nil
  @type wire_json_map :: %{optional(String.t()) => wire_json_scalar() | [wire_json_scalar()] | wire_json_map()}

  @type parity_step :: wire_json_map()

  @type normalized_model :: DebuggerTypes.wire_string_map() | String.t() | nil

  @type normalized_view_row :: DebuggerTypes.wire_string_map()

  @type msg_tag_index :: %{optional(String.t()) => integer()}

  @type timeline_sample :: DebuggerTypes.wire_string_map() | nil

  @type elmx_compile_bundle :: %{
          required(:manifest) => DebuggerTypes.elmx_manifest(),
          required(:revision) => String.t(),
          required(:module) => module()
        }

  @type elmc_compile_bundle :: %{
          required(:out_dir) => String.t(),
          required(:tags) => msg_tag_index()
        }

  @type prepare_error ::
          ElmEx.Frontend.Bridge.Types.bridge_error()
          | {:elmx_compile_failed, Elmx.Types.compile_error()}
          | {:elmc_compile_failed, Elmc.CLI.Types.compile_error()}
          | {:elmc_subprocess_no_ok, String.t()}
          | {:elmc_subprocess_failed, integer(), String.t()}

  @type elmc_runner_error ::
          :cc_not_available
          | ElmcHostHarness.compile_error()
          | ElmcHostHarness.run_capture_error()
          | {:invalid_harness_json, Jason.DecodeError.t() | String.t(), String.t()}

  @type elmx_runner_error ::
          ElmEx.Frontend.Bridge.Types.bridge_error()
          | Elmx.Types.compile_error()
          | String.t()
          | atom()

  @type runner_error :: prepare_error() | elmc_runner_error() | elmx_runner_error()
end
