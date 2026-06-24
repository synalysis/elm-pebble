defmodule Ide.Mcp.DebuggerTemplateCorpus.Types do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Mcp.ToolTypes

  @type wire_map :: DebuggerTypes.wire_map()
  @type app_model :: DebuggerTypes.app_model()
  @type view_tree :: DebuggerTypes.view_output_tree()

  @typedoc "Raw or normalized debugger corpus snapshot (string-keyed JSON shape)."
  @type corpus_snapshot :: wire_map()

  @typedoc "Normalized snapshot after volatile keys and time fields are stripped."
  @type normalized_snapshot :: wire_map()

  @type render_tree_summary :: %{
          optional(String.t()) => String.t() | non_neg_integer() | [String.t()]
        }

  @type svg_op_wire :: wire_map()
  @type preview_diagnostics :: wire_map()

  @type render_tree_payload :: ToolTypes.render_tree_result() | wire_map()
  @type simulator_extras :: wire_map()

  @type normalized_json ::
          String.t()
          | boolean()
          | nil
          | float()
          | integer()
          | [normalized_json()]
          | %{optional(String.t()) => normalized_json()}

  @type render_tree_sort_key ::
          {String.t() | nil, String.t() | nil, String.t() | nil, String.t() | nil}
          | normalized_json()

  @type background_drain_error :: {:background_drain_timeout, String.t()}

  @type corpus_error :: String.t() | File.posix() | background_drain_error()
end
