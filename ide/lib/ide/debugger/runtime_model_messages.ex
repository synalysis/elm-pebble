defmodule Ide.Debugger.RuntimeModelMessages do
  @moduledoc false

  alias Ide.Debugger.Types

  @spec wire_constructor(Types.wire_input()) :: String.t() | nil
  def wire_constructor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  def wire_constructor(_message), do: nil
end
