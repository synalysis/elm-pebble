defmodule Elmc.Backend.CCodegen.GenericReachability do
  @moduledoc false

  alias Elmc.Backend.CCodegen.FusedNativeReachability
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec reachable_targets(
          [Types.function_decl_key()],
          Types.function_decl_map(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key())
        ) :: MapSet.t(Types.function_decl_key())
  def reachable_targets(roots, decl_map, excluded_targets, seen \\ MapSet.new()) do
    do_reachable(roots, decl_map, excluded_targets, seen)
  end

  @spec wrapper_reachable_targets(
          [Types.function_decl_key()],
          Types.function_decl_map(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key())
        ) :: MapSet.t(Types.function_decl_key())
  def wrapper_reachable_targets(roots, decl_map, excluded_targets, seen \\ MapSet.new()) do
    do_wrapper_reachable(roots, decl_map, excluded_targets, seen)
  end

  defp do_reachable([], _decl_map, _excluded_targets, seen), do: seen

  defp do_reachable([target | rest], decl_map, excluded_targets, seen) do
    cond do
      MapSet.member?(excluded_targets, target) ->
        callees =
          case Map.fetch(decl_map, target) do
            {:ok, decl} ->
              case FusedNativeReachability.callees(elem(target, 0), elem(target, 1), decl.expr, decl_map) do
                keys when is_list(keys) -> keys
                nil -> expr_callees(decl.expr, elem(target, 0), decl_map)
              end

            :error ->
              []
          end

        do_reachable(rest ++ callees, decl_map, excluded_targets, seen)

      MapSet.member?(seen, target) ->
        do_reachable(rest, decl_map, excluded_targets, seen)

      not Map.has_key?(decl_map, target) ->
        do_reachable(rest, decl_map, excluded_targets, seen)

      true ->
        decl = Map.fetch!(decl_map, target)

        callees =
          case FusedNativeReachability.callees(elem(target, 0), elem(target, 1), decl.expr, decl_map) do
            keys when is_list(keys) -> keys
            nil -> expr_callees(decl.expr, elem(target, 0), decl_map)
          end

        do_reachable(
          rest ++ callees,
          decl_map,
          excluded_targets,
          MapSet.put(seen, target)
        )
    end
  end

  defp do_wrapper_reachable([], _decl_map, _excluded_targets, seen), do: seen

  defp do_wrapper_reachable([target | rest], decl_map, excluded_targets, seen) do
    cond do
      MapSet.member?(excluded_targets, target) ->
        callees =
          case Map.fetch(decl_map, target) do
            {:ok, decl} ->
              case FusedNativeReachability.callees(elem(target, 0), elem(target, 1), decl.expr, decl_map) do
                keys when is_list(keys) -> keys
                nil -> expr_wrapper_callees(decl.expr, elem(target, 0), decl_map)
              end

            :error ->
              []
          end

        do_wrapper_reachable(rest ++ callees, decl_map, excluded_targets, seen)

      MapSet.member?(seen, target) ->
        do_wrapper_reachable(rest, decl_map, excluded_targets, seen)

      not Map.has_key?(decl_map, target) ->
        do_wrapper_reachable(rest, decl_map, excluded_targets, seen)

      true ->
        decl = Map.fetch!(decl_map, target)

        callees =
          case FusedNativeReachability.callees(elem(target, 0), elem(target, 1), decl.expr, decl_map) do
            keys when is_list(keys) -> keys
            nil -> expr_wrapper_callees(decl.expr, elem(target, 0), decl_map)
          end

        do_wrapper_reachable(
          rest ++ callees,
          decl_map,
          excluded_targets,
          MapSet.put(seen, target)
        )
    end
  end

  @spec expr_callees(Types.ir_expr() | nil, String.t(), Types.function_decl_map()) :: [
          Types.function_decl_key()
        ]
  def expr_callees(expr, module_name, decl_map) do
    expr
    |> expr_callees_list(module_name, decl_map)
    |> Enum.uniq()
  end

  @spec expr_wrapper_callees(Types.ir_expr() | nil, String.t(), Types.function_decl_map()) :: [
          Types.function_decl_key()
        ]
  def expr_wrapper_callees(expr, module_name, decl_map) do
    expr
    |> expr_wrapper_callees_list(module_name, decl_map)
    |> Enum.uniq()
  end

  defp expr_wrapper_callees_list(expr, module_name, decl_map) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: name, args: args} ->
          target = {module_name, name}

          cond do
            not Map.has_key?(decl_map, target) -> []
            native_function_call_target?(target, args || [], decl_map) -> []
            true -> [target]
          end

        %{op: :qualified_call, target: target, args: args} ->
          case Host.special_value_from_target(target, args || []) do
            nil ->
              case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
                nil ->
                  []

                target_key ->
                  cond do
                    not Map.has_key?(decl_map, target_key) -> []
                    native_function_call_target?(target_key, args || [], decl_map) -> []
                    true -> [target_key]
                  end
              end

            rewritten ->
              expr_wrapper_callees_list(rewritten, module_name, decl_map)
          end

        %{op: :var, name: name} ->
          target = {module_name, name}
          if Map.has_key?(decl_map, target), do: [target], else: []

        _ ->
          []
      end

    child_callees =
      expr
      |> wrapper_callee_child_values()
      |> Enum.flat_map(&expr_wrapper_callees_list(&1, module_name, decl_map))

    own ++ child_callees
  end

  defp expr_wrapper_callees_list(values, module_name, decl_map) when is_list(values) do
    Enum.flat_map(values, &expr_wrapper_callees_list(&1, module_name, decl_map))
  end

  defp expr_wrapper_callees_list(_value, _module_name, _decl_map), do: []

  defp expr_callees_list(expr, module_name, decl_map) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: name} ->
          target = {module_name, name}
          if Map.has_key?(decl_map, target), do: [target], else: []

        %{op: :qualified_call, target: target, args: args} ->
          case Host.special_value_from_target(target, args || []) do
            nil ->
              case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
                nil -> []
                target_key -> if Map.has_key?(decl_map, target_key), do: [target_key], else: []
              end

            rewritten ->
              expr_callees_list(rewritten, module_name, decl_map)
          end

        %{op: :var, name: name} ->
          target = {module_name, name}
          if Map.has_key?(decl_map, target), do: [target], else: []

        _ ->
          []
      end

    child_callees =
      expr
      |> Map.values()
      |> Enum.flat_map(&expr_callees_list(&1, module_name, decl_map))

    own ++ child_callees
  end

  defp expr_callees_list(values, module_name, decl_map) when is_list(values) do
    Enum.flat_map(values, &expr_callees_list(&1, module_name, decl_map))
  end

  defp expr_callees_list(_value, _module_name, _decl_map), do: []

  defp wrapper_callee_child_values(%{op: op, args: args})
       when op in [:call, :qualified_call, :runtime_call, :constructor_call, :field_call] and
              is_list(args),
       do: args

  defp wrapper_callee_child_values(expr), do: Map.values(expr)

  @spec native_function_call_target?(
          Types.function_decl_key(),
          [Types.ir_expr()],
          Types.function_decl_map()
        ) :: boolean()
  defp native_function_call_target?(target, args, decl_map) do
    case Map.fetch(decl_map, target) do
      {:ok, decl} ->
        length(args || []) == length(decl.args || []) and
          Host.native_function_args?(decl, elem(target, 0), decl_map)

      :error ->
        false
    end
  end
end
