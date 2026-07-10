defmodule Elmc.Backend.Plan.Lower.UnionCtor do
  @moduledoc false

  alias Elmc.Backend.Plan.Context

  @spec qualify(String.t(), Context.t() | map() | nil) :: String.t()
  def qualify(name, ctx) when is_binary(name) do
    if String.contains?(name, ".") do
      name
    else
      case module_name(ctx) do
        mod when is_binary(mod) -> "#{mod}.#{name}"
        _ -> name
      end
    end
  end

  defp module_name(%Context{module: mod}) when is_binary(mod), do: mod
  defp module_name(%{module: mod}) when is_binary(mod), do: mod
  defp module_name(_), do: nil
end
