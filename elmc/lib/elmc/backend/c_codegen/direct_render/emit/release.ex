defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Release do
  @moduledoc false

  @spec release_vars([String.t()], String.t()) :: String.t()
  def release_vars([], _indent), do: ""

  def release_vars(vars, indent) do
    vars
    |> Enum.map_join("\n", fn var -> "#{indent}elmc_release(#{var});" end)
  end
end
