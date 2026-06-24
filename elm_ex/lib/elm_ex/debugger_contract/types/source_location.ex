defmodule ElmEx.DebuggerContract.Types.SourceLocation do
  @moduledoc """
  Source span attached to view-tree call nodes (`path`, `line`, `call`).
  """

  @type t :: %{
          optional(atom()) => String.t() | integer() | nil,
          optional(String.t()) => String.t() | integer() | nil
        }
end
