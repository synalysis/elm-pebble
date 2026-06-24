defmodule Ide.Mcp.Types do
  @moduledoc false

  alias Ide.Compiler.Cache, as: CompileCache
  alias Ide.Compiler.ManifestCache
  alias Ide.Mcp.CheckCache
  alias Ide.Mcp.WireTypes

  @type stdio_read_error ::
          :missing_content_length
          | :unexpected_eof
          | Jason.DecodeError.t()
          | atom()

  @type audit_entry :: %{
          optional(atom()) => WireTypes.json_value(),
          optional(String.t()) => WireTypes.json_value()
        }

  @type audit_action_count :: %{
          required(:action) => String.t(),
          required(:total) => non_neg_integer(),
          required(:ok) => non_neg_integer(),
          required(:error) => non_neg_integer()
        }

  @type policy_finding :: %{
          required(:severity) => String.t(),
          required(:code) => String.t(),
          required(:message) => String.t()
        }

  @type compiler_history_entry ::
          CheckCache.cached_entry()
          | CompileCache.entry()
          | ManifestCache.entry()

  @type trace_compiler_latest :: %{
          required(:check) => compiler_history_entry() | nil,
          required(:compile) => compiler_history_entry() | nil,
          required(:manifest) => compiler_history_entry() | nil
        }

  @type trace_compiler_recent :: %{
          required(:checks) => [compiler_history_entry()],
          required(:compiles) => [compiler_history_entry()],
          required(:manifests) => [compiler_history_entry()]
        }

  @type trace_bundle_args :: %{optional(String.t()) => WireTypes.json_value()}

  @type traces_summary_window :: %{
          required(:limit) => pos_integer(),
          required(:audit_entries) => non_neg_integer(),
          required(:checks) => non_neg_integer(),
          required(:compiles) => non_neg_integer(),
          required(:manifests) => non_neg_integer()
        }

  @type traces_summary_latest_status :: %{
          required(:check) => :ok | :error | String.t() | nil,
          required(:compile) => :ok | :error | String.t() | nil,
          required(:manifest) => :ok | :error | String.t() | nil,
          required(:manifest_strict) => boolean() | nil
        }

  @typedoc """
  MCP vector tool success payloads (string-keyed JSON objects).
  """
  @type vector_tool_result :: %{optional(String.t()) => WireTypes.json_value()}
end
