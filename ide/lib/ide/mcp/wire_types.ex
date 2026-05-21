defmodule Ide.Mcp.WireTypes do
  @moduledoc """
  Shared wire/input types for MCP JSON arguments and tool-side normalizers.
  """

  @type scalar :: String.t() | integer() | float() | boolean() | nil

  @type json_value :: scalar() | [json_value()] | %{optional(String.t()) => json_value()}

  @type optional_string :: String.t() | nil

  @type limit_input :: pos_integer() | String.t() | nil

  @type since_input :: String.t() | nil

  @type slug_input :: String.t() | nil

  @type trace_id_input :: String.t() | nil

  @type cursor_seq_input :: non_neg_integer() | String.t() | nil

  @type boolean_input :: boolean() | String.t() | nil

  @type integer_input :: integer() | String.t() | nil

  @type float_input :: float() | integer() | String.t() | nil

  @type sha256_input :: String.t() | nil

  @type replay_mode_input :: String.t() | nil

  @type event_types_input :: [String.t()] | String.t() | nil

  @type debugger_targets_input :: [String.t()] | String.t() | nil

  @type render_tree_target_input :: String.t() | atom() | nil

  @type platform_target_input :: String.t() | atom() | nil

  @type debugger_setting_value :: json_value()

  @type map_value_result :: json_value()
end
