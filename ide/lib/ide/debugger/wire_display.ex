defmodule Ide.Debugger.WireDisplay do
  @moduledoc false

  alias Ide.Debugger.Types

  @doc """
  Formats runtime / protocol wire values for debugger timeline and inbound labels.

  Uses the same Elm-style rules as `Elmx.Runtime.Core.Debug` (records, dicts, booleans, lists).
  """
  @spec format(Types.wire_input()) :: String.t()
  def format(value), do: Elmx.Runtime.Core.Debug.to_string(value)
end
