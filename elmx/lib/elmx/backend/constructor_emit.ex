defmodule Elmx.Backend.ConstructorEmit do
  @moduledoc """
  Maps IR union constructor entries to emit-time expression nodes.

  Uses `ConstructorLookup` metadata and `SpecialValues.rewrite/2` on each entry's
  `qualified` target; remaining shapes are derived from payload kind and union type.
  """

  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Types

  @spec rewrite(Elmx.Backend.ConstructorLookup.entry()) :: Types.rewrite_result()
  def rewrite(%{payload_kind: :none} = entry), do: rewrite_none(entry)

  def rewrite(%{payload_kind: :single, constructor: name}) do
    {:ok,
     %{
       op: :lambda,
       args: ["__ctor_arg__"],
       body: %{op: :constructor_call, name: name, args: [%{op: :var, name: "__ctor_arg__"}]}
     }}
  end

  def rewrite(_), do: :error

  @spec rewrite_none(Elmx.Backend.ConstructorLookup.entry()) :: Types.rewrite_result()
  defp rewrite_none(entry) do
    case SpecialValues.rewrite(entry.qualified, []) do
      {:ok, %{op: :runtime_call} = node} ->
        {:ok, node}

      {:ok, %{op: :string_literal}} ->
        rewrite_string_special(entry)

      :error ->
        rewrite_plain_none(entry)
    end
  end

  @spec rewrite_string_special(Elmx.Backend.ConstructorLookup.entry()) :: {:ok, Types.ir_expr()}
  defp rewrite_string_special(entry) do
    if label_union?(entry) do
      {:ok, %{op: :string_literal, value: entry.constructor}}
    else
      {:ok, %{op: :int_literal, value: entry.tag}}
    end
  end

  @spec rewrite_plain_none(Elmx.Backend.ConstructorLookup.entry()) :: {:ok, Types.ir_expr()}
  defp rewrite_plain_none(entry) do
    cond do
      label_union?(entry) ->
        {:ok, %{op: :string_literal, value: entry.constructor}}

      true ->
        {:ok, %{op: :constructor_call, name: entry.constructor, args: []}}
    end
  end

  @spec label_union?(Elmx.Backend.ConstructorLookup.entry()) :: boolean()
  defp label_union?(entry) do
    union_type = Map.get(entry, :union_type) || ""
    String.ends_with?(union_type, ".Label")
  end
end
