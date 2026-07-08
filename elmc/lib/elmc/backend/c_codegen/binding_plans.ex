defmodule Elmc.Backend.CCodegen.BindingPlans do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.UsageAnalysis, as: NativeUsageAnalysis
  alias Elmc.Backend.CCodegen.SchemaRegistry
  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.CCodegen.Types

  @scalar_kinds ~w(int float bool char)a

  @type binding_key :: {String.t(), String.t(), String.t()}

  @spec analyze(Types.function_decl_map(), SchemaRegistry.t() | nil) :: %{
          binding_key() => StoragePlan.t()
        }
  def analyze(decl_map, _registry \\ nil) when is_map(decl_map) do
    decl_map
    |> Enum.flat_map(fn {{mod, fun}, decl} ->
      analyze_function_bindings(mod, fun, decl.expr, decl_map)
    end)
    |> Map.new()
  end

  defp analyze_function_bindings(mod, fun, expr, decl_map) do
    walk_bindings(mod, fun, expr, decl_map, [])
  end

  defp walk_bindings(mod, fun, %{op: :let_in, name: name, value_expr: value, in_expr: body}, decl_map, stack)
       when is_binary(name) do
    plan = binding_plan(mod, fun, name, value, body, decl_map)

    rest =
      walk_bindings(mod, fun, body, decl_map, [{name, value} | stack])

    if plan do
      [{ {mod, fun, name}, plan} | rest]
    else
      rest
    end
  end

  defp walk_bindings(mod, fun, expr, decl_map, stack) when is_map(expr) do
    case expr do
      %{op: :let_in} ->
        []

      _ ->
        expr
        |> Map.values()
        |> Enum.flat_map(&walk_bindings(mod, fun, &1, decl_map, stack))
    end
  end

  defp walk_bindings(_mod, _fun, _expr, _decl_map, _stack), do: []

  defp binding_plan(mod, fun, name, value_expr, in_expr, decl_map) do
    env = %{__module__: mod, __function_name__: fun, __program_decls__: decl_map}

    cond do
      native_usage_let?(:int, name, value_expr, in_expr, env) ->
        StoragePlan.scalar_unboxed(:int)

      native_usage_let?(:float, name, value_expr, in_expr, env) ->
        StoragePlan.scalar_unboxed(:float)

      NativeUsageAnalysis.bool_let?(name, value_expr, in_expr, env) ->
        StoragePlan.scalar_unboxed(:bool)

      true ->
        nil
    end
  end

  defp native_usage_let?(:int, name, value_expr, in_expr, env) do
    usage =
      NativeUsageAnalysis.int_usage(
        name,
        in_expr,
        Map.get(env, :__module__),
        Map.get(env, :__program_decls__, %{})
      )

    value_native? =
      NativeInt.native_let_value_expr?(value_expr, env)

    value_native? and NativeUsageAnalysis.native_int_only_usage?(usage)
  end

  defp native_usage_let?(:float, name, value_expr, in_expr, env) do
    NativeUsageAnalysis.float_let?(to_string(name), value_expr, in_expr, env)
  end

  @spec binding_plan(String.t(), String.t(), String.t()) :: StoragePlan.t() | nil
  def binding_plan(module, fun, name)
      when is_binary(module) and is_binary(fun) and is_binary(name) do
    case Process.get(:elmc_storage_plans) do
      %{binding_plans: plans} -> Map.get(plans, {module, fun, name})
      _ -> nil
    end
  end

  @spec scalar_unboxed?(String.t(), String.t(), String.t(), atom()) :: boolean()
  def scalar_unboxed?(module, fun, name, kind)
      when is_binary(module) and is_binary(fun) and is_binary(name) and kind in @scalar_kinds do
    case binding_plan(module, fun, name) do
      %StoragePlan{elem: {:primitive, ^kind}, layout: :unboxed} -> true
      _ -> false
    end
  end

  def scalar_unboxed?(_module, _fun, _name, _kind), do: false
end
