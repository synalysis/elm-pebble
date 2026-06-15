defmodule Elmc.Backend.Pebble.IRAnalysis.RandomGenerate do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.IRAnalysis.RandomGenerate.Walker
  alias Elmc.Backend.Pebble.Types

  @spec target_tag(IR.t(), Types.msg_constructor_list()) :: Types.msg_tag()
  def target_tag(%IR{} = ir, msg_constructors) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      Walker.target_names(Map.get(declaration, :expr) || Map.get(declaration, :body))
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) ->
        tag

      name ->
        Enum.find_value(msg_constructors, fn
          {^name, tag} -> tag
          _ -> nil
        end)
    end)
  end
end
