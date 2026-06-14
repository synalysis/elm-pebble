defmodule Elmc.Backend.Pebble.AccelConfig.Resolve.Expr do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.Types

  @spec resolve(CCodegenTypes.ir_expr(), Types.record_literal_bindings()) ::
          CCodegenTypes.ir_expr()
  def resolve(%{op: :var, name: name}, bindings) do
    Map.get(bindings, name, %{op: :unknown})
  end

  def resolve(%{op: :qualified_var, target: target}, bindings) do
    target
    |> String.split(".")
    |> List.last()
    |> then(&Map.get(bindings, &1, %{op: :unknown}))
  end

  def resolve(expr, _bindings), do: expr

  @spec int_field(CCodegenTypes.ir_expr(), String.t(), pos_integer()) :: pos_integer()
  def int_field(%{op: :record_literal, fields: fields}, field, default)
      when is_list(fields) do
    case Enum.find(fields, &(&1.name == field)) do
      %{expr: %{op: :int_literal, value: value}} when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end

  def int_field(%{op: :var, name: _name}, _field, default), do: default
  def int_field(_, _field, default), do: default
end
