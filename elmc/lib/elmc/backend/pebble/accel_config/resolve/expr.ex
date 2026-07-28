defmodule Elmc.Backend.Pebble.AccelConfig.Resolve.Expr do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.Types

  @spec resolve(CCodegenTypes.ir_expr(), Types.record_literal_bindings()) ::
          CCodegenTypes.ir_expr()
  def resolve(%{op: :var, name: name}, bindings) do
    Map.get(bindings, name) ||
      Elmc.Backend.CCodegen.UnsupportedSurface.unsupported_expr(%{
        kind: :expr,
        target: name,
        detail: "accel config binding miss"
      })
  end

  def resolve(%{op: :qualified_var, target: target}, bindings) do
    short =
      target
      |> String.split(".")
      |> List.last()

    Map.get(bindings, short) ||
      Elmc.Backend.CCodegen.UnsupportedSurface.unsupported_expr(%{
        kind: :expr,
        target: target,
        detail: "accel config binding miss"
      })
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
