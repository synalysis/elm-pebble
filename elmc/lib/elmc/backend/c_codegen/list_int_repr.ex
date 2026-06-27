defmodule Elmc.Backend.CCodegen.ListIntRepr do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.FusionSupport
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ImmortalStaticList
  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.RowSliceAdjacentMerge
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Types

  defp function_return_type(type), do: TypeParsing.function_return_type(type)

  @type repr :: :int_list | :float_list | :mixed

  @int_list_runtime_ops ~w(
    elmc_list_from_int_array
    elmc_list_replace_nth_int
    elmc_int_list_tail_take
    elmc_list_take
    elmc_list_drop
    elmc_list_reverse
  )

  @int_list_qualified_ops ~w(
    List.take
    List.drop
    List.reverse
    Elm.Kernel.List.take
    Elm.Kernel.List.drop
    Elm.Kernel.List.reverse
  )

  @repeat_targets ~w(List.repeat Elm.Kernel.List.repeat)

  @default_seq_config %{list_type: "List Int", compact: :int_list}

  @tuple_first_targets ~w(Tuple.first Elm.Kernel.Tuple.first)

  @indexed_map_targets ~w(
    List.indexedMap
    List.map
    Elm.Kernel.List.indexedMap
    Elm.Kernel.List.map
  )

  @spec analyze_param_sites(Types.function_decl_map()) :: %{{String.t(), String.t(), String.t()} => repr()}
  def analyze_param_sites(decl_map) when is_map(decl_map) do
    analyze(decl_map).param_repr
  end

  @spec analyze(Types.function_decl_map()) :: %{
          param_repr: %{{String.t(), String.t(), String.t()} => repr()},
          field_repr: %{{String.t(), String.t(), String.t()} => repr()}
        }
  def analyze(decl_map) when is_map(decl_map) do
    sites = collect_call_sites(decl_map)
    params = list_int_params(decl_map)
    fields = int_list_record_fields()

    {param_repr, field_repr} =
      do_combined_fixed_point(params, fields, sites, decl_map, %{}, %{})

    %{param_repr: param_repr, field_repr: field_repr}
  end

  @spec analyze_float(Types.function_decl_map()) :: %{
          param_repr: map(),
          field_repr: map()
        }
  def analyze_float(decl_map) when is_map(decl_map) do
    with_seq_config(%{list_type: "List Float", compact: :float_list}, fn ->
      analyze(decl_map)
    end)
  end

  @spec with_seq_config(map(), (-> term())) :: term()
  def with_seq_config(config, fun) when is_map(config) and is_function(fun, 0) do
    prev = Process.get(:elmc_list_seq_config)

    Process.put(:elmc_list_seq_config, Map.merge(@default_seq_config, config))

    try do
      fun.()
    after
      if prev, do: Process.put(:elmc_list_seq_config, prev), else: Process.delete(:elmc_list_seq_config)
    end
  end

  defp seq_config, do: Process.get(:elmc_list_seq_config, @default_seq_config)
  defp list_type, do: seq_config().list_type
  defp compact_repr, do: seq_config().compact
  defp compact_repr?(repr), do: repr == compact_repr()

  @spec param_repr(String.t(), String.t(), String.t()) :: repr()
  def param_repr(module, fun, arg_name)
      when is_binary(module) and is_binary(fun) and is_binary(arg_name) do
    LayoutSolver.legacy_param_repr(module, fun, arg_name)
  end

  @spec expr_repr(Types.ir_expr(), Types.function_decl_map(), keyword()) :: repr()
  def expr_repr(expr, decl_map, opts \\ []) when is_map(decl_map) do
    ctx = %{
      param_repr: Keyword.get(opts, :param_repr, %{}),
      field_repr: Keyword.get(opts, :field_repr, %{}),
      locals: Keyword.get(opts, :locals, %{}),
      caller: Keyword.get(opts, :caller),
      resolve_fields?: Keyword.get(opts, :resolve_fields?, true)
    }

    expr_repr_impl(expr, decl_map, ctx)
  end

  @spec dual_path?(repr()) :: boolean()
  def dual_path?(repr), do: !compact_repr?(repr)

  @spec consolidate([repr()]) :: repr()
  def consolidate(reprs) when is_list(reprs) do
    if reprs != [] and Enum.all?(reprs, &(&1 == compact_repr())) do
      compact_repr()
    else
      :mixed
    end
  end


  defp ctx_locals(ctx), do: Map.get(ctx, :locals, %{})
  defp ctx_param(ctx), do: Map.get(ctx, :param_repr, %{})
  defp ctx_field(ctx), do: Map.get(ctx, :field_repr, %{})
  defp ctx_caller(ctx), do: Map.get(ctx, :caller)
  defp ctx_put_locals(ctx, locals), do: Map.put(ctx, :locals, locals)

  defp record_field_key(record_type, env, field) when is_binary(record_type) and is_binary(field) do
    {mod, record} = split_record_type_key(record_type, env)
    {mod, record, field}
  end

  defp do_combined_fixed_point(params, fields, sites, decl_map, param_ctx, field_ctx) do
    write_index = index_field_writes(decl_map, fields, param_ctx, field_ctx)

    next_param =
      Map.new(params, fn key ->
        {key, param_repr_from_sites(key, sites, decl_map, param_ctx, field_ctx)}
      end)

    next_field =
      Map.new(fields, fn key ->
        {key, field_repr_from_writes(Map.get(write_index, key, []), decl_map, param_ctx, field_ctx)}
      end)

    if next_param == param_ctx and next_field == field_ctx do
      {next_param, next_field}
    else
      do_combined_fixed_point(params, fields, sites, decl_map, next_param, next_field)
    end
  end

  defp index_field_writes(decl_map, fields, param_ctx, field_ctx) do
    field_set = MapSet.new(fields)

    Enum.reduce(decl_map, %{}, fn {{decl_mod, decl_fun}, decl}, acc ->
      ctx = field_write_ctx(decl_mod, decl_fun, param_ctx, field_ctx)
      env = %{__program_decls__: decl_map, __module__: decl_mod}

      collect_field_writes_multi(
        decl.expr,
        field_set,
        env,
        ctx,
        decl_map,
        decl_mod,
        decl_fun,
        acc
      )
    end)
  end

  defp field_repr_from_writes(writes, decl_map, param_ctx, field_ctx) do
    writes
    |> Enum.reject(&field_roundtrip_on_param?/1)
    |> Enum.map(fn {expr, ctx} ->
      expr_repr(expr, decl_map,
        param_repr: param_ctx,
        field_repr: field_ctx,
        locals: ctx_locals(ctx),
        caller: ctx_caller(ctx),
        resolve_fields?: false
      )
    end)
    |> consolidate()
  end

  defp field_write_ctx(mod, fun, param_ctx, field_ctx) do
    %{
      param_repr: param_ctx,
      field_repr: field_ctx,
      locals: %{},
      caller: {mod, fun},
      resolve_fields?: false
    }
  end

  defp collect_field_writes_multi(expr, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc) do
    case expr do
      %{op: :let_in, name: name, value_expr: value, in_expr: body} when is_binary(name) ->
        ctx = extend_locals_for_binding(%{name: name, expr: value}, ctx, decl_map)

        acc =
          collect_field_writes_multi(value, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc)

        collect_field_writes_multi(body, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc)

      %{op: :record_literal} = literal ->
        acc_record_writes(literal, field_set, env, ctx, acc)

      %{op: :record_update} = update ->
        if record_type_in_field_set?(update, field_set, env) do
          acc_record_writes(update, field_set, env, ctx, acc)
        else
          fold_field_writes_multi(update, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc)
        end

      _ ->
        fold_field_writes_multi(expr, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc)
    end
  end

  defp acc_record_writes(record_expr, field_set, env, ctx, acc) do
    Enum.reduce(field_set, acc, fn {mod, record, field} = key, inner_acc ->
      if record_expr_matches_type?(record_expr, record, %{env | __module__: mod}) do
        case Expr.record_field_expr(record_expr, field) do
          nil -> inner_acc
          field_expr -> Map.update(inner_acc, key, [{field_expr, ctx}], &[{field_expr, ctx} | &1])
        end
      else
        inner_acc
      end
    end)
  end

  defp record_type_in_field_set?(record_expr, field_set, env) do
    Enum.any?(field_set, fn {mod, record, _field} ->
      record_expr_matches_type?(record_expr, record, %{env | __module__: mod})
    end)
  end

  defp fold_field_writes_multi(map, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc)
       when is_map(map) do
    case map do
      %{op: :let_in} ->
        acc

      _ ->
        Enum.reduce(map, acc, fn
          {_key, value}, inner_acc ->
            collect_field_writes_multi(value, field_set, env, ctx, decl_map, caller_mod, caller_fun, inner_acc)
        end)
    end
  end

  defp fold_field_writes_multi(list, field_set, env, ctx, decl_map, caller_mod, caller_fun, acc)
       when is_list(list) do
    Enum.reduce(list, acc, fn value, inner_acc ->
      collect_field_writes_multi(value, field_set, env, ctx, decl_map, caller_mod, caller_fun, inner_acc)
    end)
  end

  defp fold_field_writes_multi(_other, _field_set, _env, _ctx, _decl_map, _caller_mod, _caller_fun, acc), do: acc

  defp field_roundtrip_on_param?(%{op: :field_access, field: field, arg: arg}) when is_binary(field) do
    case field_access_arg_name(arg) do
      name when is_binary(name) -> true
      _ -> false
    end
  end

  defp field_roundtrip_on_param?(_expr), do: false

  defp field_access_arg_name(name) when is_binary(name), do: name
  defp field_access_arg_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp field_access_arg_name(_arg), do: nil

  defp normalize_field_access(%{op: :field_access, arg: arg, field: field} = fa) when is_binary(field) do
    %{fa | arg: Expr.normalize_field_access_arg(arg)}
  end

  defp int_list_record_fields do
    Process.get(:elmc_record_field_types, %{})
    |> Enum.flat_map(fn {{mod, record}, fields} ->
      for {field, type} <- fields,
          list_elem_type?(to_string(type)),
          do: {mod, record, to_string(field)}
    end)
  end

  defp param_repr_from_sites({mod, fun, arg}, sites, decl_map, param_ctx, field_ctx) do
    case Map.get(decl_map, {mod, fun}) do
      %{type: _type, args: _param_names} ->
        raw_sites = Map.get(sites, {mod, fun, arg}, [])

        filtered_sites =
          raw_sites
          |> Enum.reject(fn {caller_mod, caller_fun, arg_expr, _let_bindings} ->
            caller_mod == mod and caller_fun == fun and
              cons_tail_var?(decl_map, mod, fun, arg, arg_expr)
          end)
          |> Enum.reject(&superseded_fusion_call_site?(&1, {mod, fun}, decl_map))

        site_reprs =
          Enum.map(filtered_sites, fn {caller_mod, caller_fun, arg_expr, let_bindings} ->
            ctx = call_site_ctx(caller_mod, caller_fun, let_bindings, param_ctx, field_ctx, decl_map)

            expr_repr(arg_expr, decl_map,
              param_repr: param_ctx,
              field_repr: field_ctx,
              locals: ctx_locals(ctx),
              caller: ctx_caller(ctx),
              resolve_fields?: true
            )
          end)

        cond do
          site_reprs != [] ->
            consolidate(site_reprs)

          raw_sites != [] and Enum.all?(raw_sites, &superseded_fusion_call_site?(&1, {mod, fun}, decl_map)) ->
            raw_sites
            |> Enum.map(fn {caller_mod, caller_fun, arg_expr, let_bindings} ->
              ctx = call_site_ctx(caller_mod, caller_fun, let_bindings, param_ctx, field_ctx, decl_map)

              expr_repr(arg_expr, decl_map,
                param_repr: param_ctx,
                field_repr: field_ctx,
                locals: ctx_locals(ctx),
                caller: ctx_caller(ctx),
                resolve_fields?: true
              )
            end)
            |> consolidate()

          true ->
            :mixed
        end

      _ ->
        :mixed
    end
  end

  defp list_int_params(decl_map) do
    for {{mod, name}, decl} <- decl_map,
        is_binary(decl.type),
        {arg, idx} <- Enum.with_index(decl.args || []),
        list_elem_type?(Enum.at(TypeParsing.function_arg_types(decl.type), idx)) do
      {mod, name, arg}
    end
  end

  defp collect_call_sites(decl_map) do
    Enum.reduce(decl_map, %{}, fn {{mod, fun}, decl}, acc ->
      walk_expr_for_calls(decl.expr, mod, fun, acc, decl_map, [])
    end)
  end

  defp walk_expr_for_calls(expr, caller_mod, caller_fun, acc, decl_map, let_bindings) do
    case expr do
      %{op: :let_in, name: name, value_expr: value, in_expr: body} when is_binary(name) ->
        acc = walk_expr_for_calls(value, caller_mod, caller_fun, acc, decl_map, let_bindings)
        walk_expr_for_calls(body, caller_mod, caller_fun, acc, decl_map, [{name, value} | let_bindings])

      _ ->
        acc =
          case expr do
            %{op: :call, name: name, args: args} when is_binary(name) ->
              record_call_sites(caller_mod, caller_fun, name, args, acc, decl_map, let_bindings)

            %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
              record_qualified_call_sites(caller_mod, caller_fun, target, args, acc, decl_map, let_bindings)

            _ ->
              acc
          end

        fold_subexprs(expr, caller_mod, caller_fun, acc, decl_map, let_bindings)
    end
  end

  defp fold_subexprs(%{op: :let_in}, _caller_mod, _caller_fun, acc, _decl_map, _let_bindings), do: acc

  defp fold_subexprs(map, caller_mod, caller_fun, acc, decl_map, let_bindings) when is_map(map) do
    Enum.reduce(map, acc, fn
      {_key, value}, inner_acc ->
        walk_expr_for_calls(value, caller_mod, caller_fun, inner_acc, decl_map, let_bindings)
    end)
  end

  defp fold_subexprs(list, caller_mod, caller_fun, acc, decl_map, let_bindings) when is_list(list) do
    Enum.reduce(list, acc, &walk_expr_for_calls(&1, caller_mod, caller_fun, &2, decl_map, let_bindings))
  end

  defp fold_subexprs(_other, _caller_mod, _caller_fun, acc, _decl_map, _let_bindings), do: acc

  defp record_call_sites(caller_mod, caller_fun, name, args, acc, decl_map, let_bindings) do
    case Map.get(decl_map, {caller_mod, name}) do
      %{args: param_names} when is_list(param_names) ->
        zip_call_args(caller_mod, caller_fun, {caller_mod, name}, param_names, args || [], acc, let_bindings)

      _ ->
        acc
    end
  end

  defp record_qualified_call_sites(caller_mod, caller_fun, target, args, acc, decl_map, let_bindings) do
    case resolve_callee(target, caller_mod) do
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

  defp zip_call_args(caller_mod, caller_fun, {mod, name}, param_names, args, acc, let_bindings) do
    param_names
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {param, idx}, inner_acc ->
      case Enum.at(args, idx) do
        nil ->
          inner_acc

        arg_expr ->
          key = {mod, name, param}
          site = {caller_mod, caller_fun, resolve_let_arg(arg_expr, let_bindings), let_bindings}
          Map.update(inner_acc, key, [site], &[site | &1])
      end
    end)
  end

  defp let_bindings_map(let_bindings) when is_list(let_bindings) do
    let_bindings
    |> Enum.reverse()
    |> Enum.into(%{})
  end

  defp resolve_let_arg(%{op: :field_access, arg: _arg, field: field} = fa, let_bindings)
       when is_binary(field) do
  fa = normalize_field_access(fa)

    case fa.arg do
      %{op: :var, name: name} when is_binary(name) ->
        case Map.get(let_bindings_map(let_bindings), name) do
          %{op: :qualified_call} = bound ->
            %{fa | arg: bound}

          bound when is_map(bound) ->
            resolve_let_arg(%{fa | arg: bound}, let_bindings)

          _ ->
            fa
        end

      _ ->
        fa
    end
  end

  defp resolve_let_arg(%{op: :var, name: name}, let_bindings) when is_binary(name) do
    case Map.get(let_bindings_map(let_bindings), name) do
      nil -> %{op: :var, name: name}
      bound -> resolve_let_arg(bound, let_bindings)
    end
  end

  defp resolve_let_arg(expr, _let_bindings), do: expr

  defp call_site_ctx(caller_mod, caller_fun, let_bindings, param_ctx, field_ctx, decl_map) do
    caller_locals =
      case Map.get(decl_map, {caller_mod, caller_fun}) do
        %{type: caller_type, args: caller_params} when is_binary(caller_type) ->
          callee_locals(caller_type, caller_params || [])

        _ ->
          %{}
      end

    ctx = %{
      param_repr: param_ctx,
      field_repr: field_ctx,
      locals: caller_locals,
      caller: {caller_mod, caller_fun},
      resolve_fields?: true
    }

    let_bindings
    |> Enum.reverse()
    |> Enum.reduce(ctx, fn {name, value}, acc ->
      extend_locals_for_binding(%{name: name, expr: value}, acc, decl_map)
    end)
  end

  defp resolve_callee(target, default_module) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [module, name] -> {module, name}
      [name] -> {default_module, name}
      _ -> :error
    end
  end

  defp callee_locals(type, param_names) do
    type
    |> TypeParsing.function_arg_types()
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {arg_type, idx}, acc ->
      case Enum.at(param_names, idx) do
        arg_name when is_binary(arg_name) ->
          Map.put(acc, arg_name, Host.normalize_type_name(arg_type))

        _ ->
          acc
      end
    end)
  end

  defp expr_repr_impl(%{op: :list_literal, items: []}, _decl_map, _ctx),
    do: :mixed

  defp expr_repr_impl(%{op: :list_literal, items: items}, _decl_map, _ctx)
       when is_list(items) do
    if Enum.all?(items, &match?(%{op: :int_literal, value: _}, &1)) or
         (list_type() == "List Float" and Enum.all?(items, &match?(%{op: :float_literal, value: _}, &1))) do
      compact_repr()
    else
      :mixed
    end
  end

  defp expr_repr_impl(%{op: :var, name: name}, decl_map, ctx)
       when is_binary(name) do
    locals = ctx_locals(ctx)

    cond do
      Map.get(locals, {:binding_repr, name}) == compact_repr() ->
        compact_repr()

      Map.get(locals, name) == list_type() ->
        case ctx_caller(ctx) do
          {mod, fun} -> Map.get(ctx_param(ctx), {mod, fun, name}, :mixed)
          _ -> :mixed
        end

      true ->
        module =
          case ctx_caller(ctx) do
            {mod, _} -> mod
            _ -> "Main"
          end

        zero_arg_int_list_fn_repr({module, name}, decl_map)
    end
  end

  defp expr_repr_impl(%{op: :field_access, arg: _arg, field: field} = expr, decl_map, ctx)
       when is_binary(field) do
    %{op: :field_access, arg: arg, field: field} = normalize_field_access(expr)

    case arg do
      %{op: :qualified_call, target: target, args: args} ->
        fused_call_cells_field_repr(target, args, field, decl_map, ctx)

      %{op: :var, name: name} ->
        if Map.get(ctx_locals(ctx), {:field_repr, name, field}) == compact_repr() do
          :int_list
        else
          field_access_from_record_type(arg, field, decl_map, ctx)
        end

      _ ->
        field_access_from_record_type(arg, field, decl_map, ctx)
    end
  end

  defp expr_repr_impl(%{op: :call, name: name, args: args}, decl_map, ctx)
       when is_binary(name) do
    callee_return_list_repr(
      {Map.get(ctx_locals(ctx), :__module__, "Main"), name},
      args,
      decl_map,
      ctx
    )
  end

  defp expr_repr_impl(%{op: :qualified_call, target: target, args: args}, decl_map, ctx)
       when is_binary(target) do
    cond do
      target in @tuple_first_targets and is_list(args) ->
        case args do
          [arg] -> tuple_first_repr(arg, decl_map, ctx)
          _ -> :mixed
        end

      true ->
        with :mixed <- qualified_list_repr(target, args, decl_map, ctx),
             {mod, name} <- resolve_callee(target, Map.get(ctx_locals(ctx), :__module__, "Main")),
             %{} = decl <- Map.get(decl_map, {mod, name}) do
          callee_return_list_repr({mod, name}, args, decl, decl_map, ctx)
        else
          r -> if r == compact_repr(), do: compact_repr(), else: :mixed
        end
    end
  end

  defp expr_repr_impl(%{op: :runtime_call, function: function, args: args}, decl_map, ctx)
       when is_binary(function) and is_list(args) do
    cond do
      function in @int_list_runtime_ops and function != "elmc_list_replace_nth_int" ->
        compact_repr()

      function == "elmc_list_replace_nth_int" ->
        case args do
          [list | _] ->
            if expr_repr_impl(list, decl_map, ctx) == compact_repr(),
              do: compact_repr(),
              else: :mixed

          _ ->
            :mixed
        end

      true ->
        :mixed
    end
  end

  defp expr_repr_impl(%{op: :let, bindings: bindings, body: body}, decl_map, ctx)
       when is_list(bindings) do
    bindings
    |> Enum.reduce(ctx, fn binding, acc ->
      extend_locals_for_binding(binding, acc, decl_map)
    end)
    |> then(&expr_repr_impl(body, decl_map, &1))
  end

  defp expr_repr_impl(%{op: :let_in, name: name, value_expr: value, in_expr: body}, decl_map, ctx)
       when is_binary(name) do
    ctx =
      extend_locals_for_binding(%{name: name, expr: value}, ctx, decl_map)

    expr_repr_impl(body, decl_map, ctx)
  end

  defp expr_repr_impl(%{op: :tuple_first_expr, arg: arg}, decl_map, ctx) do
    case tuple_first_cells_repr(arg, decl_map, ctx) do
      r -> if r == compact_repr(), do: compact_repr(), else: expr_repr_impl(arg, decl_map, ctx)
    end
  end

  defp expr_repr_impl(%{op: :tuple_second_expr, arg: arg}, decl_map, ctx) do
    expr_repr_impl(arg, decl_map, ctx)
  end

  defp expr_repr_impl(_expr, _decl_map, _ctx), do: :mixed

  defp fused_call_cells_field_repr(target, args, field, decl_map, ctx) when is_binary(field) do
    with {mod, name} <- resolve_callee(target, module_from_ctx(ctx)),
         true <- fused_record_cells_field?({mod, name}, Map.get(decl_map, {mod, name}), decl_map),
         [list_arg | _] <- args || [],
         true <- expr_repr_impl(list_arg, decl_map, ctx) == compact_repr() do
      compact_repr()
    else
      _ -> :mixed
    end
  end

  defp field_access_from_record_type(arg, field, decl_map, ctx) do
    env = %{__program_decls__: decl_map}
    locals = ctx_locals(ctx)

    lt = list_type()

    case {record_type_for_arg(arg, locals, env), field_type_for_record(arg, field, locals, env)} do
      {record_type, ^lt} when is_binary(record_type) ->
        key = record_field_key(record_type, env, field)
        cr = compact_repr()

        case Map.get(ctx_field(ctx), key) do
          ^cr -> compact_repr()
          _ -> :mixed
        end

      _ ->
        :mixed
    end
  end

  defp extend_locals_for_binding(%{name: name, expr: expr}, ctx, decl_map)
       when is_binary(name) do
    repr = expr_repr_impl(expr, decl_map, ctx)
    locals = ctx_locals(ctx)

    locals =
      if repr == compact_repr(), do: Map.put(locals, name, list_type()), else: locals

    locals = Map.put(locals, {:binding_expr, name}, expr)

    locals =
      if repr == compact_repr() do
        Map.put(locals, {:binding_repr, name}, compact_repr())
      else
        locals
      end

    locals =
      if tuple_first_spawn_cells_repr(expr, decl_map, ctx) == compact_repr() do
        locals
        |> Map.put(name, list_type())
        |> Map.put({:binding_repr, name}, compact_repr())
      else
        locals
      end

    ctx = ctx_put_locals(ctx, locals)

    case expr do
      %{op: :qualified_call, target: target, args: args} ->
        maybe_bind_fused_record_cells_field(name, target, args, ctx, decl_map)

      _ ->
        ctx
    end
  end

  defp extend_locals_for_binding(_binding, ctx, _decl_map), do: ctx

  defp maybe_bind_fused_record_cells_field(binding, target, args, ctx, decl_map) do
    with {mod, name} <- resolve_callee(target, "Main"),
         true <- fused_record_cells_field?({mod, name}, Map.get(decl_map, {mod, name}), decl_map),
         [arg | _] <- args || [],
         true <- expr_repr_impl(arg, decl_map, ctx) == compact_repr() do
      ctx_put_locals(ctx, Map.put(ctx_locals(ctx), {:field_repr, binding, "cells"}, compact_repr()))
    else
      _ -> ctx
    end
  end

  defp tuple_first_repr(arg, decl_map, ctx) do
    if tuple_first_cells_repr(arg, decl_map, ctx) == compact_repr(), do: compact_repr(), else: :mixed
  end

  defp tuple_first_cells_repr(expr, decl_map, ctx) do
    case follow_binding_expr(expr, ctx) do
      %{op: :qualified_call, target: target, args: args} ->
        tuple_first_of_call_repr(target, args, decl_map, ctx)

      %{op: :call, name: name, args: args} when is_binary(name) ->
        tuple_first_of_call_repr(name, args, decl_map, ctx)

      _ ->
        :mixed
    end
  end

  defp tuple_first_of_call_repr(target, args, decl_map, ctx) when is_binary(target) do
    mod = module_from_ctx(ctx)

    with {callee_mod, name} <- resolve_callee(target, mod),
         %{} = decl <- Map.get(decl_map, {callee_mod, name}) do
      cond do
        name == "spawnTileWithSeed" ->
          case spawn_cells_arg(args) do
            cells when is_map(cells) ->
              if expr_repr_impl(cells, decl_map, ctx) == compact_repr(), do: compact_repr(), else: :mixed

            _ ->
              :mixed
          end

        tuple_pair_first_is_list_int?(decl.type) ->
          tuple_fn_first_component_repr(decl, args, decl_map, ctx)

        true ->
          :mixed
      end
    else
      _ -> :mixed
    end
  end

  defp tuple_fn_first_component_repr(%{type: type, expr: body, args: param_names}, args, decl_map, ctx) do
    if int_list_args_satisfied?(args, param_names || [], type, decl_map, ctx) and
         tuple_body_first_component_int_list?(body, decl_map, ctx) do
      :int_list
    else
      :mixed
    end
  end

  defp tuple_body_first_component_int_list?(%{op: :qualified_call, target: target, args: spawn_args}, decl_map, ctx) do
    tuple_first_of_call_repr(target, spawn_args, decl_map, ctx) == compact_repr()
  end

  defp tuple_body_first_component_int_list?(%{op: :call, name: name, args: spawn_args}, decl_map, ctx) do
    tuple_first_of_call_repr(name, spawn_args, decl_map, ctx) == compact_repr()
  end

  defp tuple_body_first_component_int_list?(%{op: :let_in, name: name, value_expr: value, in_expr: body}, decl_map, ctx)
       when is_binary(name) do
    ctx = extend_locals_for_binding(%{name: name, expr: value}, ctx, decl_map)
    tuple_body_first_component_int_list?(body, decl_map, ctx)
  end

  defp tuple_body_first_component_int_list?(_body, _decl_map, _ctx), do: false

  defp tuple_pair_first_is_list_int?(type) when is_binary(type) do
    type
    |> String.replace(" ", "")
    |> String.starts_with?("(ListInt,")
  end

  defp tuple_pair_first_is_list_int?(_), do: false

  defp spawn_cells_arg([_seed, cells | _]), do: cells
  defp spawn_cells_arg(_), do: nil

  defp follow_binding_expr(%{op: :var, name: name}, ctx) when is_binary(name) do
    case Map.get(ctx_locals(ctx), {:binding_expr, name}) do
      nil -> %{op: :var, name: name}
      bound -> follow_binding_expr(bound, ctx)
    end
  end

  defp follow_binding_expr(expr, _ctx), do: expr

  defp tuple_first_spawn_cells_repr(
         %{op: :tuple_first_expr, arg: arg},
         decl_map,
         ctx
       ) do
    tuple_first_cells_repr(arg, decl_map, ctx)
  end

  defp tuple_first_spawn_cells_repr(
         %{op: :qualified_call, target: target, args: [arg]},
         decl_map,
         ctx
       )
       when target in @tuple_first_targets do
    tuple_first_cells_repr(arg, decl_map, ctx)
  end

  defp tuple_first_spawn_cells_repr(_expr, _decl_map, _ctx), do: :mixed

  defp module_from_ctx(ctx) do
    case ctx_caller(ctx) do
      {mod, _} -> mod
      _ -> "Main"
    end
  end

  defp callee_return_list_repr({mod, name}, args, decl, decl_map, ctx) do
    %{type: type, expr: body, args: param_names} = decl

    if list_elem_type?(function_return_type(type)) do
      cond do
        fusion_int_list_return?({mod, name}, body, decl_map) and
            int_list_args_satisfied?(args, param_names, type, decl_map, ctx) ->
          :int_list

        immortal_int_list_return?({mod, name}, body) ->
          :int_list

        indexed_map_preserves_int_list?(body) and
            int_list_args_satisfied?(args, param_names, type, decl_map, ctx) ->
          :int_list

        true ->
          callee_locals = callee_locals(type, param_names || [])

          body_ctx = ctx_put_locals(ctx, Map.merge(ctx_locals(ctx), callee_locals))

          body_repr = expr_repr_impl(body, decl_map, body_ctx)

          if body_repr == compact_repr() do
            :int_list
          else
            call_args_preserves_int_list?(args, param_names, decl_map, ctx)
          end
      end
    else
      :mixed
    end
  end

  defp callee_return_list_repr({mod, name}, args, decl_map, ctx) do
    case Map.get(decl_map, {mod, name}) do
      %{} = decl -> callee_return_list_repr({mod, name}, args, decl, decl_map, ctx)
      _ -> :mixed
    end
  end

  defp call_args_preserves_int_list?(call_args, param_names, decl_map, ctx) do
    lt = list_type()
    cr = compact_repr()

    param_names
    |> Enum.zip(call_args || [])
    |> Enum.find_value(:mixed, fn
      {param, arg} ->
        case {Map.get(ctx_locals(ctx), param), expr_repr_impl(arg, decl_map, ctx)} do
          {^lt, ^cr} -> compact_repr()
          _ -> nil
        end
    end)
  end

  defp int_list_args_satisfied?(args, param_names, type, decl_map, ctx) do
    arg_types = TypeParsing.function_arg_types(type)

    param_names
    |> Enum.zip(args || [])
    |> Enum.zip(arg_types)
    |> Enum.all?(fn
      {{_param, arg}, arg_type} ->
        if list_elem_type?(arg_type) do
          expr_repr_impl(arg, decl_map, ctx) == compact_repr()
        else
          true
        end
    end)
  end

  defp qualified_list_repr(target, args, decl_map, ctx) do
    cond do
      target in @repeat_targets ->
        case args do
          [_, literal] -> if repeat_literal_compact?(literal), do: compact_repr(), else: :mixed
          _ -> :mixed
        end

      target in @int_list_qualified_ops ->
        case args do
          [list | _] ->
            if expr_repr_impl(list, decl_map, ctx) == compact_repr(),
              do: compact_repr(),
              else: :mixed

          _ ->
            :mixed
        end

      target in @indexed_map_targets ->
        case args do
          [_, list] ->
            if expr_repr_impl(list, decl_map, ctx) == compact_repr(),
              do: compact_repr(),
              else: :mixed

          _ ->
            :mixed
        end

      true ->
        :mixed
    end
  end

  defp fusion_int_list_return?({mod, name}, expr, decl_map) do
    case Fusion.try_emit(mod, name, expr, decl_map) do
      {:ok, _, _} -> true
      {:ok, _, _, _} -> true
      :error -> false
    end
  end

  defp fused_record_cells_field?({mod, name}, decl, decl_map) do
    case decl do
      %{expr: expr} ->
        match?({:ok, _, _}, RowSliceAdjacentMerge.try_emit(mod, name, expr, decl_map)) or
          match?({:ok, _, _, _}, RowSliceAdjacentMerge.try_emit(mod, name, expr, decl_map))

      _ ->
        false
    end
  end

  defp indexed_map_preserves_int_list?(%{op: :qualified_call, target: target, args: args})
       when target in @indexed_map_targets do
    case List.last(args || []) do
      %{name: name, op: :var} when is_binary(name) -> true
      _ -> false
    end
  end

  defp indexed_map_preserves_int_list?(_expr), do: false

  defp record_type_for_arg(name, locals, env) when is_binary(name) do
    record_type_for_arg(%{op: :var, name: name}, locals, env)
  end

  defp record_type_for_arg(%{op: :var, name: name}, locals, env) when is_binary(name) do
    case Map.get(locals, name) do
      type when is_binary(type) ->
        if type != list_type(), do: type, else: Expr.record_container_type_for_expr(%{op: :var, name: name}, env)

      _ ->
        Expr.record_container_type_for_expr(%{op: :var, name: name}, env)
    end
  end

  defp record_type_for_arg(arg, _locals, env), do: Expr.record_container_type_for_expr(arg, env)

  defp field_type_for_record(arg, field, locals, env) do
    case record_type_for_arg(arg, locals, env) do
      type when is_binary(type) ->
        field_types = Process.get(:elmc_record_field_types, %{})

        case Map.get(field_types, split_record_type_key(type, env)) do
          %{} = types -> Map.get(types, field) || Map.get(types, String.to_atom(field))
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp immortal_int_list_return?({mod, name}, body) do
    match?(
      {:ok, _, _},
      ImmortalStaticList.try_emit_function_prelude_and_body(mod, name, body, false, false)
    )
  catch
    _, _ -> static_int_list_body?(body)
  end

  defp static_int_list_body?(%{op: :list_literal, items: items}) when is_list(items),
    do: Enum.all?(items, &match?(%{op: :int_literal, value: _}, &1))

  defp static_int_list_body?(_), do: false

  defp zero_arg_int_list_fn_repr({mod, name}, decl_map) do
    case Map.get(decl_map, {mod, name}) do
      %{type: type, expr: body, args: []} when is_binary(type) ->
        if list_elem_type?(type) and
             (immortal_int_list_return?({mod, name}, body) or static_int_list_body?(body) or
                repeat_homogeneous_literal?(body)) do
          compact_repr()
        else
          :mixed
        end

      _ ->
        :mixed
    end
  end

  defp repeat_homogeneous_literal?(%{op: :qualified_call, target: target, args: [_, literal]})
       when target in @repeat_targets,
       do: repeat_literal_compact?(literal)

  defp repeat_homogeneous_literal?(_), do: false

  defp repeat_literal_compact?(%{op: :int_literal}), do: list_type() == "List Int"
  defp repeat_literal_compact?(%{op: :float_literal}), do: list_type() == "List Float"
  defp repeat_literal_compact?(_), do: false

  defp record_expr_matches_type?(expr, record_type, env) do
    case Expr.record_type_for_expr(expr, env) do
      type when is_binary(type) ->
        Host.normalize_type_name(type) == Host.normalize_type_name(record_type)

      _ ->
        false
    end
  end

  defp split_record_type_key(type, env) do
    module = Map.get(env, :__module__, "Main")

    cond do
      String.contains?(type, ".") ->
        case String.split(type, ".", parts: 2) do
          [mod, name] -> {mod, name}
          _ -> {module, type}
        end

      true ->
        {module, type}
    end
  end

  defp superseded_fusion_call_site?({caller_mod, caller_fun, _arg_expr, _let_bindings}, {callee_mod, callee_fun}, decl_map) do
    FusionSupport.superseded_fusion_callee?({caller_mod, caller_fun}, {callee_mod, callee_fun}, decl_map)
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

  defp list_elem_type?(type) when is_binary(type),
    do: Host.normalize_type_name(type) == list_type()

  defp list_elem_type?(_type), do: false
end
