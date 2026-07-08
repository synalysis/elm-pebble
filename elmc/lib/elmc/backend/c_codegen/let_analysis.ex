defmodule Elmc.Backend.CCodegen.LetAnalysis do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.UsageAnalysis, as: NativeUsageAnalysis
  alias Elmc.Backend.CCodegen.Types

  @type let_entry :: {Types.binding_name(), Types.ir_expr(), Types.ir_expr()}

  @spec analyze_function_expr(
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map()
        ) :: Types.function_let_analysis_map()
  def analyze_function_expr(expr, module_name, decl_map) do
    let_names = collect_let_names(expr)
    duplicate_names = duplicate_names(let_names)

    expr
    |> collect_let_analyses(duplicate_names, %{})
    |> Map.values()
    |> Map.new(fn {name, value_expr, in_expr} ->
      usage = NativeUsageAnalysis.int_usage(name, in_expr, module_name, decl_map)

      classification =
        cond do
          MapSet.member?(duplicate_names, name) ->
            :boxed

          NativeInt.native_let_value_expr?(value_expr, %{__module__: module_name, __program_decls__: decl_map}) and
              NativeUsageAnalysis.native_int_only_usage?(usage) ->
            :native_int

          NativeInt.structural_expr?(value_expr) or NativeInt.field_arith_expr?(value_expr) ->
            :boxed_int

          true ->
            :boxed
        end

      {name, classification}
    end)
  end

  @spec classification(Types.compile_env(), Types.binding_name()) ::
          Types.let_binding_classification()
  def classification(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__function_analysis__, %{})
    |> Map.get(name, :boxed)
  end

  def classification(_env, _name), do: :boxed

  @spec collect_let_names(Types.ir_expr()) :: [Types.binding_name()]
  defp collect_let_names(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    [name | collect_let_names(value_expr) ++ collect_let_names(in_expr)]
  end

  defp collect_let_names(expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_let_names/1)
  end

  defp collect_let_names(exprs) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_let_names/1)

  defp collect_let_names(_expr), do: []

  @spec duplicate_names([Types.binding_name()]) :: MapSet.t(Types.binding_name())
  defp duplicate_names(names) do
    names
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> MapSet.new()
  end

  @spec collect_let_analyses(
          Types.ir_expr(),
          MapSet.t(Types.binding_name()),
          %{Types.binding_name() => let_entry()}
        ) :: %{Types.binding_name() => let_entry()}
  defp collect_let_analyses(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
         duplicate_names,
         acc
       ) do
    acc
    |> Map.put(name, {name, value_expr, in_expr})
    |> then(&collect_let_analyses(value_expr, duplicate_names, &1))
    |> then(&collect_let_analyses(in_expr, duplicate_names, &1))
  end

  defp collect_let_analyses(expr, duplicate_names, acc) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.reduce(acc, &collect_let_analyses(&1, duplicate_names, &2))
  end

  defp collect_let_analyses(exprs, duplicate_names, acc) when is_list(exprs) do
    Enum.reduce(exprs, acc, &collect_let_analyses(&1, duplicate_names, &2))
  end

  defp collect_let_analyses(_expr, _duplicate_names, acc), do: acc
end
