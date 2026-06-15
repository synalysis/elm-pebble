defmodule Elmc.Backend.CCodegen.DirectRender.UseSites do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type use_sites :: Types.direct_function_use_sites()

  @spec affine_pruned_map_callback_targets(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          Types.codegen_opts()
        ) :: MapSet.t(Types.function_decl_key())
  def affine_pruned_map_callback_targets(targets, decl_map, opts) do
    entry_module = opts[:entry_module] || "Main"
    entry_view = {entry_module, "view"}
    use_sites = collect(targets, decl_map)

    Enum.reduce(targets, MapSet.new(), fn target, pruned_acc ->
      cond do
        target == entry_view ->
          pruned_acc

        map_callback_only_target?(target, use_sites) and
            map_callback_affine_inlined_everywhere?(target, use_sites, decl_map) ->
          MapSet.put(pruned_acc, target)

        true ->
          pruned_acc
      end
    end)
  end

  @spec collect(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: use_sites()
  def collect(targets, decl_map) do
    Enum.reduce(targets, %{}, fn {module_name, _decl_name} = target, acc ->
      decl = Map.fetch!(decl_map, target)
      walk(decl.expr, module_name, :normal, acc)
    end)
  end

  defp walk(expr, module_name, ctx, acc) when is_map(expr) do
    acc =
      case ctx do
        {:map, map_kind, list_expr} ->
          case resolve_reference(expr, module_name) do
            nil ->
              acc

            {target_module, target_name, prefix_args} ->
              record_use(
                {target_module, target_name},
                {:map, map_kind, prefix_args, list_expr},
                acc
              )
          end

        :normal ->
          case resolve_reference(expr, module_name) do
            nil ->
              acc

            {target_module, target_name, _prefix_args} ->
              record_use({target_module, target_name}, :other, acc)
          end
      end

    case expr do
      %{op: :qualified_call, target: target, args: [fun_expr, list_expr]} ->
        case Host.normalize_special_target(target) do
          "List.indexedMap" ->
            acc = walk(fun_expr, module_name, {:map, :indexed, list_expr}, acc)
            walk(list_expr, module_name, :normal, acc)

          "List.map" ->
            acc = walk(fun_expr, module_name, {:map, :map, list_expr}, acc)
            walk(list_expr, module_name, :normal, acc)

          "List.concatMap" ->
            acc = walk(fun_expr, module_name, {:map, :map, list_expr}, acc)
            walk(list_expr, module_name, :normal, acc)

          _ ->
            walk_children(expr, module_name, ctx, acc)
        end

      _ ->
        walk_children(expr, module_name, ctx, acc)
    end
  end

  defp walk(values, module_name, ctx, acc) when is_list(values) do
    Enum.reduce(values, acc, &walk(&1, module_name, ctx, &2))
  end

  defp walk(_value, _module_name, _ctx, acc), do: acc

  defp walk_children(expr, module_name, ctx, acc) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.reduce(acc, &walk(&1, module_name, ctx, &2))
  end

  defp resolve_reference(expr, module_name) do
    case expr do
      %{op: :var, name: name} ->
        {module_name, name, []}

      %{op: :call, name: name, args: args} ->
        {module_name, name, args || []}

      %{op: :qualified_call, target: target, args: args} ->
        case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
          {target_module, target_name} -> {target_module, target_name, args || []}
          nil -> nil
        end

      _ ->
        nil
    end
  end

  defp record_use(target, entry, acc) do
    Map.update(acc, target, [entry], &[entry | &1])
  end

  defp map_callback_only_target?(target, use_sites) do
    case Map.get(use_sites, target) do
      nil ->
        false

      entries ->
        Enum.all?(entries, fn
          {:map, _, _, _} -> true
          :other -> false
        end)
    end
  end

  defp map_callback_affine_inlined_everywhere?(target, use_sites, decl_map) do
    {target_module, target_name} = target
    decl = Map.fetch!(decl_map, target)

    use_sites
    |> Map.fetch!(target)
    |> Enum.all?(fn
      {:map, map_kind, prefix_args, list_expr} ->
        env =
          Host.direct_emit_check_env(
            decl,
            target_module,
            MapSet.new([target]),
            decl_map
          )

        map_callback_affine_inlined_at_site?(
          decl_map,
          {target_module, target_name, prefix_args},
          map_kind,
          list_expr,
          env
        )

      :other ->
        false
    end)
  end

  defp map_callback_affine_inlined_at_site?(
         decl_map,
         target,
         map_kind,
         list_expr,
         env
       ) do
    {target_module, target_name, prefix_args} = target

    case Host.direct_static_list_items(list_expr) do
      {:ok, static_items} ->
        case Host.direct_static_draw_table_loop(static_items, env, 0) do
          {:ok, _code, _counter} -> true
          :error -> false
        end

      :error ->
        case map_kind do
          :indexed ->
            case Host.direct_draw_affine_template_indexed(decl_map, target, env) do
              {:ok, _, _, _} -> true
              :error -> false
            end

          :map ->
            item_param =
              case Map.get(decl_map, {target_module, target_name}) do
                %{args: args} when is_list(args) ->
                  Enum.at(args, length(prefix_args)) || "direct_item"

                _ ->
                  "direct_item"
              end

            case Host.direct_draw_affine_template(decl_map, target, item_param, env) do
              {:ok, _} -> true
              :error -> false
            end
        end
    end
  end

  @spec single_call_prune_targets(
          MapSet.t(Types.function_decl_key()),
          use_sites(),
          Types.function_decl_map(),
          Types.codegen_opts()
        ) :: MapSet.t(Types.function_decl_key())
  def single_call_prune_targets(emit_targets, use_sites, decl_map, opts) do
    entry_module = opts[:entry_module] || "Main"
    entry_view = {entry_module, "view"}

    Enum.reduce(emit_targets, MapSet.new(), fn target, pruned_acc ->
      cond do
        target == entry_view ->
          pruned_acc

        single_other_call_only?(target, use_sites) and
            single_call_inlineable?(target, emit_targets, decl_map, opts) ->
          MapSet.put(pruned_acc, target)

        true ->
          pruned_acc
      end
    end)
  end

  @spec single_other_call_only?(Types.function_decl_key(), use_sites()) :: boolean()
  defp single_other_call_only?(target, use_sites) do
    case Map.get(use_sites, target) do
      nil ->
        false

      entries ->
        others = Enum.filter(entries, &(&1 == :other))
        maps = Enum.reject(entries, &(&1 == :other))
        length(others) == 1 and maps == []
    end
  end

  @spec single_call_inlineable?(
          Types.function_decl_key(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          Types.codegen_opts()
        ) :: boolean()
  defp single_call_inlineable?({module_name, _decl_name} = target, emit_targets, decl_map, opts) do
    decl = Map.fetch!(decl_map, target)
    env = Host.direct_emit_check_env(decl, module_name, emit_targets, decl_map)
    max_lines = opts[:direct_single_call_inline_max_lines] || 100

    case Host.direct_emit_expr(decl.expr, env, 0) do
      {:ok, code, _counter} -> emitted_line_count(code) <= max_lines
      :error -> false
    end
  end

  defp emitted_line_count(code) when is_binary(code), do: code |> String.split("\n") |> length()
end
