defmodule Elmc.Backend.Pebble.AccelConfig.Resolve.Bindings do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Types

  @spec from_ir(IR.t()) :: Types.record_literal_bindings()
  def from_ir(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(fn decl -> Map.get(decl, :kind) in [:value, :function] end)
      |> Enum.flat_map(fn decl ->
        expr = Map.get(decl, :expr) || Map.get(decl, :body)

        case expr do
          %{op: :record_literal} = record ->
            [{decl.name, record}, {"#{mod.name}.#{decl.name}", record}]

          _ ->
            []
        end
      end)
    end)
    |> Map.new()
  end
end
