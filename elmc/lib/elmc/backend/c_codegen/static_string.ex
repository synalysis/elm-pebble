defmodule Elmc.Backend.CCodegen.StaticString do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec fold_append_literals(Types.ir_expr()) :: Types.ir_expr()
  def fold_append_literals(expr), do: fold(expr)

  defp fold(%{op: :call, name: "__append__", args: [left, right]}),
    do: combine(fold(left), fold(right), &__append__/2)

  defp fold(%{op: :runtime_call, function: "elmc_append", args: [left, right]}),
    do: combine(fold(left), fold(right), &elmc_append/2)

  defp fold(expr), do: expr

  defp combine(%{op: :string_literal, value: left}, %{op: :string_literal, value: right}, _builder),
    do: %{op: :string_literal, value: left <> right}

  defp combine(
         %{op: :string_literal, value: left},
         %{op: :call, name: "__append__", args: [middle, rest]},
         builder
       ) do
    case middle do
      %{op: :string_literal, value: middle_text} ->
        fold(builder.(%{op: :string_literal, value: left <> middle_text}, rest))

      _ ->
        builder.(%{op: :string_literal, value: left}, %{op: :call, name: "__append__", args: [middle, rest]})
    end
  end

  defp combine(
         %{op: :string_literal, value: left},
         %{op: :runtime_call, function: "elmc_append", args: [middle, rest]},
         builder
       ) do
    case middle do
      %{op: :string_literal, value: middle_text} ->
        fold(builder.(%{op: :string_literal, value: left <> middle_text}, rest))

      _ ->
        builder.(
          %{op: :string_literal, value: left},
          %{op: :runtime_call, function: "elmc_append", args: [middle, rest]}
        )
    end
  end

  defp combine(left, right, builder), do: builder.(left, right)

  defp __append__(left, right), do: %{op: :call, name: "__append__", args: [left, right]}

  defp elmc_append(left, right),
    do: %{op: :runtime_call, function: "elmc_append", args: [left, right]}
end
