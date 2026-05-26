defmodule Ide.Debugger.CompanionBridge.ApiSuffixes do
  @moduledoc false

  @spec suffixes(String.t(), [String.t()]) :: [String.t()]
  def suffixes(module, ops) when is_binary(module) and is_list(ops) do
    Enum.flat_map(ops, fn op ->
      [
        ".Pebble.Companion.#{module}.#{op}",
        ".#{module}.#{op}",
        "#{module}.#{op}"
      ]
    end)
  end
end
