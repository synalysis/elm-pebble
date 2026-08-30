defmodule Elmc.Backend.Plan.Stream.StaticDrawTable do
  @moduledoc """
  Homogeneous static `list_literal` of draw ops → verified Plan stream table.

  Matches the Host `Emit.StaticDrawTable` IR shape (same kind, compile-time
  integer params) so Plan SSA can emit a table walk instead of unrolling
  each `render_cmd`.
  """
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.SpecialValues

  @min_rows 2

  @type table :: %{kind: map(), rows: [[String.t()]]}

  @spec table_shape?([term()]) :: boolean()
  def table_shape?(items) when is_list(items), do: match(items) != :error
  def table_shape?(_), do: false

  @spec match(term()) :: {:ok, table()} | :error
  def match(%{op: :list_literal, items: items}) when is_list(items), do: match(items)
  def match(%{op: :list_literal, elements: items}) when is_list(items), do: match(items)
  def match(items) when is_list(items), do: match_items(items)
  def match(_), do: :error

  @spec match_items([term()]) :: {:ok, table()} | :error
  def match_items(items) when is_list(items) and length(items) >= @min_rows do
    case Enum.map(items, &match_row/1) do
      rows when length(rows) == length(items) ->
        if Enum.all?(rows, &match?({:ok, _}, &1)) do
          parsed = Enum.map(rows, fn {:ok, row} -> row end)

          case Enum.uniq(Enum.map(parsed, & &1.kind_macro)) do
            [kind_macro] ->
              {:ok,
               %{
                 kind: %{c_expr: kind_macro},
                 rows: Enum.map(parsed, & &1.params)
               }}

            _ ->
              :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  def match_items(_), do: :error

  @spec emit(table(), Context.t(), Builder.t()) :: {:ok, :stream_void, Builder.t()}
  def emit(%{kind: kind, rows: rows}, ctx, b) when is_list(rows) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    {_, b2} =
      Builder.emit(b1, :stream_static_draw_table, %{
        dest: :stream_void,
        args: %{kind: kind, rows: rows, direct_scene_push: true},
        effects: %{produces: nil, consumes: [], borrows: [], fallible: true}
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2
    {:ok, :stream_void, b3}
  end

  defp match_row(item) do
    case rewrite_draw(item) do
      %{op: :render_cmd, kind: kind, params: params} ->
        with {:ok, kind_macro} <- kind_macro(kind),
             {:ok, ints} <- static_int_params(params) do
          {:ok, %{kind_macro: kind_macro, params: pad_params(ints)}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp rewrite_draw(%{op: :render_cmd} = expr), do: expr

  defp rewrite_draw(%{op: op} = expr) when op in [:call, :qualified_call] do
    case call_target(expr) do
      target when is_binary(target) ->
        args = List.wrap(Map.get(expr, :args))

        case SpecialValues.special_value_from_target(
               SpecialValues.normalize_special_target(target),
               args
             ) do
          %{op: :render_cmd} = rewritten -> rewritten
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp rewrite_draw(_), do: :error

  defp kind_macro(%{op: :c_int_expr, value: value}) when is_binary(value), do: {:ok, value}
  defp kind_macro(%{c_expr: value}) when is_binary(value), do: {:ok, value}

  defp kind_macro(%{op: :int_literal, value: value}) when is_integer(value),
    do: {:ok, SpecialValues.generated_draw_kind_macro(value)}

  defp kind_macro(%{literal: value}) when is_integer(value),
    do: {:ok, SpecialValues.generated_draw_kind_macro(value)}

  defp kind_macro(_), do: :error

  defp static_int_params(params) when is_list(params) do
    Enum.reduce_while(params, {:ok, []}, fn param, {:ok, acc} ->
      case static_int_ref(param) do
        {:ok, ref} -> {:cont, {:ok, acc ++ [ref]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp static_int_params(_), do: :error

  defp static_int_ref(%{op: :int_literal} = expr),
    do: {:ok, Integer.to_string(ResourceUnion.int_literal_value(expr))}

  defp static_int_ref(%{op: :c_int_expr, value: value}) when is_binary(value), do: {:ok, value}

  defp static_int_ref(%{op: :field_access, arg: arg, field: field}) when is_binary(field) do
    case record_field(arg, field) do
      nil -> :error
      expr -> static_int_ref(expr)
    end
  end

  defp static_int_ref(%{op: op} = expr)
       when op in [
              :call,
              :qualified_call,
              :qualified_ref,
              :qualified_var,
              :constructor_ref,
              :constructor_call
            ] do
    case call_target(expr) do
      target when is_binary(target) ->
        args = List.wrap(Map.get(expr, :args))
        static_int_from_target(target, args)

      _ ->
        :error
    end
  end

  defp static_int_ref(_), do: :error

  defp static_int_from_target(target, args) do
    cond do
      ResourceUnion.constructor?(target, args) ->
        {:ok, Integer.to_string(ResourceUnion.slot_index(target))}

      true ->
        case SpecialValues.special_value_from_target(
               SpecialValues.normalize_special_target(target),
               args
             ) do
          nil -> :error
          rewritten -> static_int_ref(rewritten)
        end
    end
  end

  defp record_field(%{op: :record_literal, fields: fields}, field) when is_list(fields) do
    case Enum.find(fields, fn f -> Map.get(f, :name) == field end) do
      %{expr: expr} -> expr
      %{value: value} -> value
      _ -> nil
    end
  end

  defp record_field(%{op: :record_update, base: base, fields: fields}, field) when is_list(fields) do
    case Enum.find(fields, fn f -> Map.get(f, :name) == field end) do
      %{expr: expr} -> expr
      %{value: value} -> value
      _ -> record_field(base, field)
    end
  end

  defp record_field(%{op: op} = expr, field)
       when op in [:call, :qualified_call] and is_binary(field) do
    case call_target(expr) do
      target when is_binary(target) ->
        case SpecialValues.special_value_from_target(
               SpecialValues.normalize_special_target(target),
               List.wrap(Map.get(expr, :args))
             ) do
          nil -> nil
          rewritten -> record_field(rewritten, field)
        end

      _ ->
        nil
    end
  end

  defp record_field(_, _), do: nil

  defp call_target(%{target: target}) when is_binary(target), do: target
  defp call_target(%{name: name}) when is_binary(name), do: name
  defp call_target(_), do: nil

  defp pad_params(params) do
    (params ++ ["0", "0", "0", "0", "0"]) |> Enum.take(5)
  end
end
