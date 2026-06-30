defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Release do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ValueSlots

  @spec release_var(String.t(), String.t()) :: String.t()
  def release_var(var, indent \\ "") when is_binary(var) and is_binary(indent) do
    ValueSlots.release_stmt(var)
    |> String.split("\n", trim: true)
    |> case do
      [] -> ""
      lines -> Enum.map_join(lines, "\n", &"#{indent}#{&1}")
    end
  end

  @spec release_vars([String.t()], String.t()) :: String.t()
  def release_vars([], _indent), do: ""

  def release_vars(vars, indent) do
    vars
    |> Enum.map(&release_var(&1, indent))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end
end
