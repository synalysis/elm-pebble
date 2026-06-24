defmodule ElmEx.DebuggerContract.Types.ViewTree do
  @moduledoc """
  Parser-derived debugger view tree nodes (`build_view_tree/2` output).

  Runtime maps use string keys (`"type"`, `"label"`, `"children"`, …).
  """

  alias ElmEx.DebuggerContract.Payload

  @type tree_node :: %{
          optional(atom()) => Payload.json_value() | [tree_node()],
          optional(String.t()) => Payload.json_value() | [tree_node()]
        }

  @type t :: tree_node()
  @type wire_node :: tree_node()
end
