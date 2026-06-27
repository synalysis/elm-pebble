defmodule Elmc.Backend.CCodegen.ListRecordRepr do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.FusionSupport
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.SchemaRegistry
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Types

  @type repr :: :record_seq | :mixed

  @repeat_targets ~w(List.repeat Elm.Kernel.List.repeat)

  @spec analyze(Types.function_decl_map(), SchemaRegistry.t() | nil) :: %{
          param_repr: %{{String.t(), String.t(), String.t()} => repr()},
          field_repr: %{}
        }
  def analyze(decl_map, registry \\ nil) when is_map(decl_map) do
    registry = registry || Process.get(:elmc_schema_registry) || SchemaRegistry.build_from_field_types(%{})

    params =
      for {{mod, fun}, decl} <- decl_map,
          is_binary(decl.type),
          {arg, idx} <- Enum.with_index(decl.args || []),
          type = Enum.at(TypeParsing.function_arg_types(decl.type), idx),
          not is_nil(type),
          not is_nil(record_list_elem(type, registry)) do
        {mod, fun, arg}
      end

    sites = collect_call_sites(decl_map)

    param_repr =
      Map.new(params, fn key ->
        {key, param_repr_from_sites(key, sites, decl_map, registry)}
      end)

    %{param_repr: param_repr, field_repr: %{}}
  end

  defp record_list_params_elem(decl_map, mod, fun, arg, registry) do
    case Map.get(decl_map, {mod, fun}) do
      %{type: type, args: args} when is_binary(type) ->
        case Enum.find_index(args || [], &(&1 == arg)) do
          nil ->
            nil

          idx ->
            type
            |> TypeParsing.function_arg_types()
            |> Enum.at(idx)
            |> record_list_elem(registry)
        end

      _ ->
        nil
    end
  end

  defp record_list_elem(nil, _registry), do: nil

  defp record_list_elem(type, registry) when is_binary(type) do
    type = Host.normalize_type_name(type)

    case type do
      "List " <> elem_type ->
        elem_type = Host.normalize_type_name(elem_type)

        with {:ok, {mod, record}} <- record_elem(elem_type),
             true <- SchemaRegistry.all_native?(registry, mod, record) do
          {mod, record}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp record_elem(type) do
    case String.split(type, ".", parts: 2) do
      [mod, record] -> {:ok, {mod, record}}
      [record] -> {:ok, {"Main", record}}
      _ -> :error
    end
  end

  defp collect_call_sites(decl_map) do
    Enum.reduce(decl_map, %{}, fn {{mod, fun}, decl}, acc ->
      walk_expr_for_calls(decl.expr, mod, fun, acc, decl_map, [])
    end)
  end

  defp walk_expr_for_calls(%{op: :let_in, value_expr: value, in_expr: body}, caller_mod, caller_fun, acc, decl_map, lets) do
    acc = walk_expr_for_calls(value, caller_mod, caller_fun, acc, decl_map, lets)
    walk_expr_for_calls(body, caller_mod, caller_fun, acc, decl_map, lets)
  end

  defp walk_expr_for_calls(expr, caller_mod, caller_fun, acc, decl_map, let_bindings) when is_map(expr) do
    acc =
      case expr do
        %{op: :call, name: name, args: args} when is_binary(name) ->
          record_call_sites(caller_mod, caller_fun, name, args, acc, decl_map, let_bindings)

        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          record_qualified_call_sites(caller_mod, caller_fun, target, args, acc, decl_map, let_bindings)

        _ ->
          acc
      end

    case expr do
      %{op: :let_in} -> acc
      _ -> fold_subexprs(expr, caller_mod, caller_fun, acc, decl_map, let_bindings)
    end
  end

  defp walk_expr_for_calls(_expr, _caller_mod, _caller_fun, acc, _decl_map, _let_bindings), do: acc

  defp fold_subexprs(map, caller_mod, caller_fun, acc, decl_map, let_bindings) when is_map(map) do
    Enum.reduce(map, acc, fn
      {_key, value}, inner_acc ->
        walk_expr_for_calls(value, caller_mod, caller_fun, inner_acc, decl_map, let_bindings)
    end)
  end

  defp record_call_sites(caller_mod, caller_fun, name, args, acc, decl_map, let_bindings) do
    case Map.get(decl_map, {caller_mod, name}) do
      %{args: param_names} when is_list(param_names) ->
        zip_call_args(caller_mod, caller_fun, {caller_mod, name}, param_names, args || [], acc, let_bindings)

      _ ->
        acc
    end
  end

  defp record_qualified_call_sites(caller_mod, caller_fun, target, args, acc, decl_map, let_bindings) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {mod, name} ->
        case Map.get(decl_map, {mod, name}) do
          %{args: param_names} when is_list(param_names) ->
            zip_call_args(caller_mod, caller_fun, {mod, name}, param_names, args || [], acc, let_bindings)

          _ ->
            acc
        end

      _ ->
        acc
    end
  end

  defp zip_call_args(caller_mod, caller_fun, {mod, name}, param_names, args, acc, _let_bindings) do
    Enum.with_index(param_names)
    |> Enum.reduce(acc, fn {param, idx}, inner_acc ->
      case Enum.at(args, idx) do
        nil -> inner_acc
        arg_expr ->
          site = {caller_mod, caller_fun, arg_expr}
          Map.update(inner_acc, {mod, name, param}, [site], &[site | &1])
      end
    end)
  end

  defp param_repr_from_sites({mod, fun, arg}, sites, decl_map, registry) do
    elem = record_list_params_elem(decl_map, mod, fun, arg, registry)

    sites
    |> Map.get({mod, fun, arg}, [])
    |> then(fn raw_sites ->
      filtered =
        raw_sites
        |> Enum.reject(fn {caller_mod, caller_fun, arg_expr} ->
          cons_tail_var?(decl_map, mod, fun, arg, arg_expr) or
            FusionSupport.superseded_fusion_callee?({caller_mod, caller_fun}, {mod, fun}, decl_map)
        end)

      reprs =
        Enum.map(filtered, fn {_caller_mod, _caller_fun, arg_expr} ->
          expr_repr(arg_expr, elem, decl_map, registry)
        end)

      cond do
        reprs != [] ->
          reprs

        raw_sites != [] and
            Enum.all?(raw_sites, fn {caller_mod, caller_fun, _arg_expr} ->
              FusionSupport.superseded_fusion_callee?({caller_mod, caller_fun}, {mod, fun}, decl_map)
            end) ->
          Enum.map(raw_sites, fn {_caller_mod, _caller_fun, arg_expr} ->
            expr_repr(arg_expr, elem, decl_map, registry)
          end)

        true ->
          []
      end
    end)
    |> consolidate()
  end

  defp cons_tail_var?(decl_map, mod, fun, list_arg, arg) do
    case Map.get(decl_map, {mod, fun}) do
      %{expr: %{op: :case, subject: subject, branches: branches}} ->
        tail_name =
          case cons_tail_binding(branches) do
            {:ok, _head, tail} -> tail
            _ -> nil
          end

        tail_name &&
          case_subject?(subject, list_arg) &&
          tail_var?(arg, tail_name)

      _ ->
        false
    end
  end

  defp case_subject?(subject, list_arg) when is_binary(subject), do: subject == list_arg

  defp case_subject?(%{op: :var, name: name}, list_arg) when is_binary(name),
    do: name == list_arg

  defp case_subject?(_subject, _list_arg), do: false

  defp cons_tail_binding(branches) when is_list(branches) do
    case Enum.find(branches, &cons_pattern?/1) do
      %{pattern: pattern} -> cons_bind_names(pattern)
      _ -> :error
    end
  end

  defp cons_pattern?(%{pattern: %{resolved_name: "List.::"}}), do: true
  defp cons_pattern?(%{pattern: %{name: "::", kind: :constructor}}), do: true
  defp cons_pattern?(_branch), do: false

  defp cons_bind_names(%{arg_pattern: %{kind: :tuple, elements: [_head, tail_pat]}}) do
    case tail_pat do
      %{kind: :var, name: tail} when is_binary(tail) -> {:ok, nil, tail}
      _ -> :error
    end
  end

  defp cons_bind_names(_pattern), do: :error

  defp tail_var?(%{op: :var, name: name}, tail) when is_binary(name) and is_binary(tail),
    do: name == tail

  defp tail_var?(name, tail) when is_binary(name) and is_binary(tail), do: name == tail
  defp tail_var?(_expr, _tail), do: false

  defp zero_arg_record_list_fn_repr({mod, name}, decl_map, registry) do
    case Map.get(decl_map, {mod, name}) do
      %{type: type, expr: body, args: []} when is_binary(type) ->
        elem = record_list_elem(type, registry)

        if elem && expr_repr(body, elem, decl_map, registry) == :record_seq do
          :record_seq
        else
          :mixed
        end

      _ ->
        :mixed
    end
  end

  defp expr_repr(expr, elem, decl_map, registry)

  defp expr_repr(%{op: :var, name: name}, elem, decl_map, registry)
       when is_binary(name) and is_map(decl_map) do
    module =
      case elem do
        {mod, _} -> mod
        _ -> "Main"
      end

    zero_arg_record_list_fn_repr({module, name}, decl_map, registry || SchemaRegistry.build_from_field_types(%{}))
  end

  defp expr_repr(expr, elem, _decl_map, _registry) do
    case expr do
      %{op: :list_literal, items: elements} when is_list(elements) ->
        if elem && Enum.all?(elements, &native_record_literal?(&1, elem)), do: :record_seq, else: :mixed

      %{op: :qualified_call, target: target, args: args} when target in @repeat_targets ->
        repeat_repr(args, elem)

      %{op: :call, name: "repeat", args: args} ->
        repeat_repr(args, elem)

      _ ->
        :mixed
    end
  end

  defp repeat_repr([n, value], elem) do
    if known_length?(n) and native_record_literal?(value, elem), do: :record_seq, else: :mixed
  end

  defp repeat_repr(_args, _elem), do: :mixed

  defp native_record_literal?(%{op: :record_literal} = literal, {mod, record}) do
    field_types =
      Process.get(:elmc_record_field_types, %{})
      |> Map.get({mod, record}, %{})

    field_types != %{} and
      Enum.all?(field_types, fn {field, type} ->
        native_field_literal?(literal, to_string(field), to_string(type))
      end)
  end

  defp native_record_literal?(_, _), do: false

  defp native_field_literal?(literal, field, type) do
    case Expr.record_field_expr(literal, field) do
      %{op: :int_literal} -> type == "Int"
      %{op: :float_literal} -> type == "Float"
      %{op: :bool_literal} -> type == "Bool"
      %{op: :char_literal} -> type == "Char"
      _ -> false
    end
  end

  defp known_length?(%{op: :int_literal, value: n}) when is_integer(n) and n >= 0, do: true
  defp known_length?(_), do: false

  defp consolidate(reprs) do
    if reprs != [] and Enum.all?(reprs, &(&1 == :record_seq)), do: :record_seq, else: :mixed
  end
end
