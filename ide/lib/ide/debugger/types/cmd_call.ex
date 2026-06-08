defmodule Ide.Debugger.Types.CmdCall do
  @moduledoc """
  Structured row from debugger contract `extract_cmd_calls/2` and subscription call extraction.

  Runtime maps use **string keys** (see `wire_map/0`).
  """

  alias ElmEx.DebuggerContract.Payload
  alias Ide.Debugger.Types

  @type json_value :: Payload.json_value()

  @type activation_guard :: %{
          optional(:kind) => String.t(),
          optional(:subject) => String.t(),
          optional(:branch) => String.t(),
          optional(String.t()) => json_value(),
          optional(atom()) => json_value()
        }

  @type t :: %{
          optional(:target) => String.t(),
          optional(:name) => String.t(),
          optional(:callback_constructor) => String.t() | nil,
          optional(:callback_arg_count) => non_neg_integer() | nil,
          optional(:branch_constructor) => String.t() | nil,
          optional(:event_kind) => String.t(),
          optional(:label) => String.t(),
          optional(:arg_kinds) => [String.t()],
          optional(:arg_snippets) => [String.t()],
          optional(:arg_values) => [json_value()],
          optional(:task_sources) => [String.t()],
          optional(:activation_guards) => [activation_guard()],
          optional(:kind) => String.t(),
          optional(String.t()) => json_value(),
          optional(atom()) => json_value()
        }

  @type wire_map :: t() | Types.wire_map()
end
