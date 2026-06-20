defmodule Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.UseSites
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.PlatformStatic
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.VarAnalysis

  @spec helper_let?(Types.binding_name(), Types.ir_expr(), Types.compile_env()) :: boolean()
  def helper_let?(_name, value_expr, env) do
    if TextOptions.packable_value?(value_expr) do
      false
    else
      with {:ok, _} <- field_entries(value_expr, env) do
        case value_expr do
          %{op: :record_literal} -> true
          _ -> single_non_map_use?(value_expr, env)
        end
      else
        _ -> false
      end
    end
  end

  @spec emit_fields(
          Types.binding_name(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.native_record_emit_result()
  def emit_fields(name, value_expr, env, counter) do
    case field_entries(value_expr, env) do
      {:ok, field_entries} ->
        emit_field_entries_result(name, value_expr, field_entries, env, counter)

      :error ->
        :error
    end
  end

  @spec field_entries(Types.ir_expr(), Types.compile_env()) ::
          {:ok, Types.native_record_field_entries()} | :error
  def field_entries(value_expr, env) do
    case value_expr do
      %{op: :record_literal, fields: fields} when is_list(fields) and fields != [] ->
        entries =
          Enum.map(fields, fn %{name: field_name, expr: field_expr} ->
            {field_name, field_expr}
          end)

        record_type = record_type_for_entries(entries, env)

        cond do
          hoistable_if_fields?(entries, env) ->
            {:ok, entries}

          Enum.all?(entries, fn {field, field_expr} ->
            native_record_field_expr?(field_expr, field, record_type, env)
          end) ->
            {:ok, entries}

          true ->
            :error
        end

      _ ->
        with {:ok, body_expr} <- substituted_helper_body(value_expr, env),
             field_names when field_names != [] <- helper_return_fields(value_expr, env) do
          entries =
            Enum.map(field_names, fn field ->
              {field, Host.inline_record_field_expr(body_expr, field, env)}
            end)

          if Enum.all?(entries, fn {_field, field_expr} -> not is_nil(field_expr) end) do
            {:ok, entries}
          else
            :error
          end
        else
          _ -> :error
        end
    end
  end

  defp single_non_map_use?(value_expr, env) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with target_key when not is_nil(target_key) <- Expr.record_helper_target(value_expr, env),
         entries when is_list(entries) <-
           Map.get(UseSites.collect(MapSet.new(Map.keys(decl_map)), decl_map), target_key) do
      others = Enum.filter(entries, &(&1 == :other))
      maps = Enum.reject(entries, &(&1 == :other))
      length(others) == 1 and maps == []
    else
      _ -> false
    end
  end

  defp substituted_helper_body(value_expr, env) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with target_key when not is_nil(target_key) <- Expr.record_helper_target(value_expr, env),
         %{args: arg_names, expr: body} when is_list(arg_names) <- Map.get(decl_map, target_key),
         args <- Map.get(value_expr, :args, []),
         true <- length(arg_names) == length(args) do
      {:ok, Host.substitute_expr(body, Map.new(Enum.zip(arg_names, args)))}
    else
      _ -> :error
    end
  end

  defp helper_return_fields(value_expr, env) do
    typed_fields =
      case Expr.record_helper_target(value_expr, env) do
        nil -> []
        target_key -> helper_native_int_fields(target_key, value_expr, env)
      end

    if typed_fields != [] do
      typed_fields
    else
      case substituted_helper_body(value_expr, env) do
        {:ok, body_expr} -> field_names_from_expr(body_expr)
        :error -> []
      end
    end
  end

  defp field_names_from_expr(expr) do
    {expr, _} = Host.unwrap_let_chain(expr, %{})
    field_names_from_expr_body(expr)
  end

  defp field_names_from_expr_body(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    (field_names_from_expr_body(then_expr) ++ field_names_from_expr_body(else_expr))
    |> Enum.uniq()
  end

  defp field_names_from_expr_body(%{op: :record_literal, fields: fields}) when is_list(fields) do
    Enum.map(fields, & &1.name)
  end

  defp field_names_from_expr_body(_expr), do: []

  defp helper_native_int_fields(target_key, value_expr, env) do
    arg_count = value_expr |> Map.get(:args, []) |> length()

    case Expr.record_shape_for_function_return(target_key, env, arg_count) do
      fields when is_list(fields) -> fields
      _ -> []
    end
  end

  defp emit_field_entries_result(name, value_expr, field_entries, env, counter) do
    cond do
      hoistable_if_fields?(field_entries, env) ->
        emit_hoisted_if_fields(name, value_expr, field_entries, env, counter)

      true ->
        emit_field_entries(name, value_expr, field_entries, env, counter)
    end
  end

  defp helper_record_type(value_expr, env) do
    case Expr.record_helper_target(value_expr, env) do
      nil ->
        nil

      target_key ->
        Expr.record_type_for_function_return(
          target_key,
          env,
          value_expr |> Map.get(:args, []) |> length()
        )
    end
  end

  defp hoistable_if_fields?(field_entries, env) do
    case field_entries do
      [{_field, %{op: :direct_native_if, cond: cond}} | _] ->
        record_type = record_type_for_entries(field_entries, env)

        Enum.all?(field_entries, fn
          {field,
           %{op: :direct_native_if, cond: ^cond, then_expr: then_expr, else_expr: else_expr}} ->
            native_record_field_expr?(then_expr, field, record_type, env) and
              native_record_field_expr?(else_expr, field, record_type, env) and
              field_kind(record_type, field, then_expr, env) ==
                field_kind(record_type, field, else_expr, env)

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp emit_hoisted_if_fields(name, value_expr, field_entries, env, counter) do
    hoisted_before = Process.get(:elmc_hoisted_native_ints, %{})

    try do
      [{_field, %{op: :direct_native_if, cond: cond}} | _] = field_entries

      record_type =
        Expr.record_type_for_expr(value_expr, env) ||
          record_type_for_entries(field_entries, env) ||
          helper_record_type(value_expr, env)

      {cond_code, cond_ref, cond_cleanup, counter, platform_macro} =
        case PlatformStatic.platform_static_macro(cond) do
          macro when is_binary(macro) ->
            {"", nil, "", counter, macro}

          nil ->
            {cond_code, cond_ref, cond_cleanup, counter} =
              if Host.native_bool_expr?(cond, env) do
                {code, ref, c} = Host.compile_native_bool_expr(cond, env, counter)
                {code, ref, "", c}
              else
                {code, var, c} = Host.compile_expr(cond, env, counter)
                {code, "elmc_as_int(#{var}) != 0", "  elmc_release(#{var});\n", c}
              end

            {cond_code, cond_ref, cond_cleanup, counter, nil}
        end

      counter = counter_after_emitted_code(cond_code <> cond_cleanup, counter)

      then_entries =
        Enum.map(field_entries, fn {field, %{op: :direct_native_if, then_expr: then_expr}} ->
          {field, then_expr}
        end)

      else_entries =
        Enum.map(field_entries, fn {field, %{op: :direct_native_if, else_expr: else_expr}} ->
          {field, else_expr}
        end)

      {minmax_preamble, counter} =
        precompile_branch_minmax_hoists(then_entries ++ else_entries, env, counter)

      with {:ok, then_code, then_refs, then_kinds, counter} <-
             emit_branch_fields("_then", then_entries, record_type, env, counter),
           {:ok, else_code, else_refs, _else_kinds, counter} <-
             emit_branch_fields("_else", else_entries, record_type, env, counter) do
        {field_code, field_map, counter} =
          Enum.reduce(field_entries, {"", %{}, counter}, fn
            {field, %{op: :direct_native_if}}, {code_acc, map_acc, c} ->
              next = c + 1
              var = "direct_native_record_#{Util.safe_c_suffix(name)}_#{field}_#{next}"
              then_ref = Map.fetch!(then_refs, field)
              else_ref = Map.fetch!(else_refs, field)
              kind = Map.fetch!(then_kinds, field)

              merge_code =
                if is_binary(platform_macro) do
                  platform_branch_merge_decl(kind, var, platform_macro, then_ref, else_ref)
                else
                  branch_merge_decl(kind, var, cond_ref, then_ref, else_ref)
                end
              {code_acc <> merge_code, Map.put(map_acc, field, var), next}
          end)

        body_env =
          env
          |> put_native_record_binding(name, field_map, value_expr, then_entries ++ else_entries)
          |> maybe_put_hoisted_native_bool(cond, cond_ref, platform_macro)
          |> Hoist.merge_process_hoisted_native_ints()

        {:ok, minmax_preamble <> cond_code <> cond_cleanup <> then_code <> else_code <> field_code, body_env, counter}
      else
        :error -> :error
      end
    after
      Process.put(:elmc_hoisted_native_ints, hoisted_before)
    end
  end

  defp emit_branch_fields(branch, field_entries, record_type, env, counter) do
    if field_entries == [] do
      {:ok, "", %{}, %{}, counter}
    else
      emit_branch_fields_impl(branch, field_entries, record_type, env, counter)
    end
  end

  defp precompile_branch_minmax_hoists(field_entries, env, counter) do
    env = Hoist.merge_process_hoisted_native_ints(env)

    field_entries
    |> Enum.map(&elem(&1, 1))
    |> Enum.flat_map(&branch_minmax_exprs(&1, []))
    |> Enum.uniq()
    |> Enum.reduce({"", counter}, fn expr, {code_acc, c} ->
      case Host.hoisted_native_int_lookup(env, expr) do
        {:ok, _ref} ->
          {code_acc, c}

        :error ->
          {expr_code, _ref, c2} = Host.compile_native_int_expr(expr, env, c)
          {code_acc <> expr_code, c2}
      end
    end)
  end

  defp branch_minmax_exprs(expr, acc) when is_map(expr) do
    acc =
      case expr do
        %{op: :call, name: name, args: [_, _]} when name in ["min", "max"] ->
          [expr | acc]

        %{op: :qualified_call, target: target, args: [_, _]}
        when target in ["Basics.min", "Basics.max"] ->
          [expr | acc]

        %{op: :runtime_call, function: function, args: [_, _]}
        when function in ["elmc_basics_min", "elmc_basics_max"] ->
          [expr | acc]

        _ ->
          acc
      end

    Enum.reduce(expr, acc, fn
      {_key, value}, acc when is_map(value) or is_list(value) ->
        branch_minmax_exprs(value, acc)

      _, acc ->
        acc
    end)
  end

  defp branch_minmax_exprs(expr, acc) when is_list(expr) do
    Enum.reduce(expr, acc, &branch_minmax_exprs(&1, &2))
  end

  defp branch_minmax_exprs(_expr, acc), do: acc

  defp emit_branch_fields_impl(branch, field_entries, record_type, env, counter) do
    env = Hoist.merge_process_hoisted_native_ints(env)

    Process.put(
      :elmc_hoisted_native_ints,
      Map.merge(
        Process.get(:elmc_hoisted_native_ints, %{}),
        Map.get(env, :__hoisted_native_ints__, %{})
      )
    )

    field_entries = sort_branch_field_entries(field_entries)
    field_sources = Map.new(field_entries)

    result =
      Enum.reduce_while(field_entries, {:ok, "", %{}, %{}, %{}, counter}, fn
        {field, field_expr}, {:ok, code_acc, refs_acc, kinds_acc, span_hoists, c} ->
          compile_env = Hoist.merge_process_hoisted_native_ints(env)
          field_expr = substitute_emitted_branch_field_calls(field_expr, refs_acc)

          field_expr =
            substitute_emitted_branch_field_subexprs(field_expr, refs_acc, field_sources)

          field_expr = rewrite_branch_value_hoists(field_expr, compile_env)

          {span_code, field_expr, span_hoists, c} =
            ensure_branch_span_hoists(field_expr, refs_acc, span_hoists, field_sources, c)

          kind = field_kind(record_type, field, field_expr, env)
          var = "direct_native_record_branch_#{branch}_#{field}_#{c}"

          case emit_native_field_value(field_expr, kind, var, env, c) do
            {:ok, code, ref, c2} ->
              if register_branch_field_hoist?(field_expr) and
                   Hoist.hoisted_native_ints_enabled?(env) do
                Host.register_hoisted_native_int(field_expr, ref)
              end

              {:cont,
               {:ok, code_acc <> span_code <> code, Map.put(refs_acc, field, ref),
                Map.put(kinds_acc, field, kind), span_hoists, c2}}

            :error ->
              {:halt, :error}
          end
      end)

    case result do
      {:ok, code, refs, kinds, _span_hoists, counter} -> {:ok, code, refs, kinds, counter}
      :error -> :error
    end
  end

  defp branch_merge_decl("String", var, cond_ref, then_ref, else_ref) do
    "  const char *#{var} = (#{cond_ref}) ? #{then_ref} : #{else_ref};\n"
  end

  defp branch_merge_decl("Float", var, cond_ref, then_ref, else_ref) do
    "  const double #{var} = (#{cond_ref}) ? #{then_ref} : #{else_ref};\n"
  end

  defp branch_merge_decl(_kind, var, cond_ref, then_ref, else_ref) do
    "  const elmc_int_t #{var} = (#{cond_ref}) ? #{then_ref} : #{else_ref};\n"
  end

  defp platform_branch_merge_decl("String", var, macro, then_ref, else_ref) do
    """
      #if defined(#{macro})
      const char *#{var} = #{then_ref};
      #else
      const char *#{var} = #{else_ref};
      #endif
    """
  end

  defp platform_branch_merge_decl("Float", var, macro, then_ref, else_ref) do
    """
      #if defined(#{macro})
      const double #{var} = #{then_ref};
      #else
      const double #{var} = #{else_ref};
      #endif
    """
  end

  defp platform_branch_merge_decl(_kind, var, macro, then_ref, else_ref) do
    """
      #if defined(#{macro})
      const elmc_int_t #{var} = #{then_ref};
      #else
      const elmc_int_t #{var} = #{else_ref};
      #endif
    """
  end

  defp maybe_put_hoisted_native_bool(env, cond, cond_ref, nil),
    do: Hoist.put_hoisted_native_bool(env, cond, cond_ref)

  defp maybe_put_hoisted_native_bool(env, _cond, _cond_ref, _macro), do: env

  defp sort_branch_field_entries(field_entries) do
    names = MapSet.new(Enum.map(field_entries, &elem(&1, 0)))
    sources = Map.new(field_entries)

    zero_arg_deps =
      Map.new(field_entries, fn {field, expr} ->
        {field,
         branch_field_zero_arg_call_deps(expr, names, []) |> Enum.uniq() |> List.delete(field)}
      end)

    subexpr_deps = branch_field_subexpr_deps(field_entries, sources)

    deps =
      Map.merge(zero_arg_deps, subexpr_deps, fn _field, zero, sub ->
        Enum.uniq(zero ++ sub)
      end)

    sort_branch_field_entries_by_deps(field_entries, deps, [])
  end

  defp branch_field_subexpr_deps(field_entries, sources) do
    Enum.reduce(field_entries, %{}, fn {field_b, expr_b}, acc ->
      deps =
        for {field_a, expr_a} <- sources,
            field_a != field_b,
            not trivial_branch_field_literal?(expr_a),
            expr_contains?(expr_b, expr_a),
            do: field_a

      if deps == [], do: acc, else: Map.put(acc, field_b, Enum.uniq(deps))
    end)
  end

  defp trivial_branch_field_literal?(%{op: :int_literal}), do: true
  defp trivial_branch_field_literal?(%{op: :char_literal}), do: true
  defp trivial_branch_field_literal?(_), do: false

  defp expr_contains?(haystack, needle) do
    case ir_expr_equal?(haystack, needle) do
      true ->
        true

      false ->
        cond do
          is_map(haystack) ->
            Enum.any?(haystack, fn
              {_key, value} when is_map(value) or is_list(value) ->
                expr_contains?(value, needle)

              _ ->
                false
            end)

          is_list(haystack) ->
            Enum.any?(haystack, &expr_contains?(&1, needle))

          true ->
            false
        end
    end
  end

  defp ir_expr_equal?(left, right), do: normalize_ir_expr(left) == normalize_ir_expr(right)

  defp normalize_ir_expr(expr) when is_map(expr) do
    expr
    |> Map.drop([:loc, :meta, :range])
    |> Enum.sort()
    |> Enum.map(fn {key, value} -> {key, normalize_ir_expr(value)} end)
    |> Map.new()
  end

  defp normalize_ir_expr(expr) when is_list(expr), do: Enum.map(expr, &normalize_ir_expr/1)
  defp normalize_ir_expr(expr), do: expr

  defp sort_branch_field_entries_by_deps([], _deps, acc), do: Enum.reverse(acc)

  defp sort_branch_field_entries_by_deps(remaining, deps, acc) do
    ready =
      remaining
      |> Enum.filter(fn {field, _} ->
        Enum.all?(Map.get(deps, field, []), &(&1 in acc))
      end)
      |> Enum.sort_by(&branch_field_emit_priority/1)

    case ready do
      [] -> Enum.reverse(acc) ++ remaining
      _ -> sort_branch_field_entries_by_deps(remaining -- ready, deps, acc ++ ready)
    end
  end

  defp branch_field_emit_priority({_field, expr}),
    do: if(trivial_branch_field_literal?(expr), do: 0, else: 1)

  defp branch_field_zero_arg_call_deps(expr, names, acc)

  defp branch_field_zero_arg_call_deps(%{op: :var, name: name}, names, acc)
       when is_binary(name) or is_atom(name) do
    key = EnvBindings.binding_key(name)
    if MapSet.member?(names, key), do: [key | acc], else: acc
  end

  defp branch_field_zero_arg_call_deps(%{op: :call, name: name, args: args}, names, acc)
       when is_binary(name) and args in [[], nil] do
    if MapSet.member?(names, name), do: [name | acc], else: acc
  end

  defp branch_field_zero_arg_call_deps(
         %{op: :qualified_call, target: target, args: args},
         names,
         acc
       )
       when is_binary(target) and args in [[], nil] do
    case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
      {_mod, name} -> if MapSet.member?(names, name), do: [name | acc], else: acc
      _ -> acc
    end
  end

  defp branch_field_zero_arg_call_deps(expr, names, acc) when is_map(expr) do
    Enum.reduce(expr, acc, fn {_key, value}, acc ->
      branch_field_zero_arg_call_deps(value, names, acc)
    end)
  end

  defp branch_field_zero_arg_call_deps(expr, names, acc) when is_list(expr),
    do: Enum.reduce(expr, acc, &branch_field_zero_arg_call_deps(&1, names, &2))

  defp branch_field_zero_arg_call_deps(_expr, _names, acc), do: acc

  defp substitute_emitted_branch_field_calls(expr, field_map) when map_size(field_map) == 0,
    do: expr

  defp substitute_emitted_branch_field_calls(expr, field_map) when is_map(expr) do
    case expr do
      %{op: :var, name: name} when is_binary(name) or is_atom(name) ->
        case Map.fetch(field_map, EnvBindings.binding_key(name)) do
          {:ok, ref} -> %{op: :c_int_expr, value: ref}
          :error -> substitute_emitted_branch_field_calls_map(expr, field_map)
        end

      %{op: :call, name: name, args: []} when is_binary(name) ->
        case Map.fetch(field_map, name) do
          {:ok, ref} -> %{op: :c_int_expr, value: ref}
          :error -> substitute_emitted_branch_field_calls_map(expr, field_map)
        end

      %{op: :qualified_call, target: target, args: []} when is_binary(target) ->
        case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
          {_mod, name} ->
            case Map.fetch(field_map, name) do
              {:ok, ref} -> %{op: :c_int_expr, value: ref}
              :error -> substitute_emitted_branch_field_calls_map(expr, field_map)
            end

          _ ->
            substitute_emitted_branch_field_calls_map(expr, field_map)
        end

      _ ->
        substitute_emitted_branch_field_calls_map(expr, field_map)
    end
  end

  defp substitute_emitted_branch_field_calls(expr, field_map) when is_list(expr),
    do: Enum.map(expr, &substitute_emitted_branch_field_calls(&1, field_map))

  defp substitute_emitted_branch_field_calls(expr, _field_map), do: expr

  defp substitute_emitted_branch_field_subexprs(expr, refs_acc, field_sources) do
    replacements =
      refs_acc
      |> Enum.flat_map(fn {field, ref} ->
        case Map.fetch(field_sources, field) do
          {:ok, source} ->
            if trivial_branch_field_literal?(source) do
              []
            else
              [{source, %{op: :c_int_expr, value: ref}}]
            end

          :error ->
            []
        end
      end)
      |> Enum.sort_by(fn {source, _} -> ir_expr_size(source) end, :desc)

    Enum.reduce(replacements, expr, &substitute_subexpr(&2, &1))
  end

  defp ir_expr_size(expr) when is_map(expr),
    do: 1 + Enum.sum(Enum.map(expr, fn {_k, v} -> ir_expr_size(v) end))

  defp ir_expr_size(expr) when is_list(expr), do: Enum.sum(Enum.map(expr, &ir_expr_size/1))
  defp ir_expr_size(_), do: 1

  defp substitute_subexpr(expr, {source, replacement}) do
    if ir_expr_equal?(expr, source) do
      replacement
    else
      substitute_subexpr_children(expr, source, replacement)
    end
  end

  defp substitute_subexpr_children(expr, source, replacement) when is_map(expr) do
    expr
    |> Map.new(fn
      {key, value} when is_map(value) or is_list(value) ->
        {key, substitute_subexpr(value, {source, replacement})}

      {key, value} ->
        {key, value}
    end)
  end

  defp substitute_subexpr_children(expr, source, replacement) when is_list(expr),
    do: Enum.map(expr, &substitute_subexpr(&1, {source, replacement}))

  defp substitute_subexpr_children(expr, _source, _replacement), do: expr

  defp ensure_branch_span_hoists(expr, refs_acc, span_hoists, field_sources, counter) do
    ensure_branch_span_hoists(expr, refs_acc, span_hoists, field_sources, counter, "")
  end

  defp ensure_branch_span_hoists(expr, refs_acc, span_hoists, field_sources, counter, code_acc)
       when is_map(expr) do
    case branch_span_key(expr, refs_acc, field_sources) do
      {:ok, key, left_field, width, right_field, gap} ->
        case Map.fetch(span_hoists, key) do
          {:ok, ref} ->
            {code_acc, %{op: :c_int_expr, value: ref}, span_hoists, counter}

          :error ->
            next = counter + 1
            ref = "direct_native_record_branch_span_#{next}"
            left_ref = branch_span_ref(refs_acc, field_sources, left_field)
            right_ref = branch_span_ref(refs_acc, field_sources, right_field)

            decl =
              "  const elmc_int_t #{ref} = ((#{left_ref} * #{width}) + (#{right_ref} * #{gap}));\n"

            {code_acc <> decl, %{op: :c_int_expr, value: ref}, Map.put(span_hoists, key, ref),
             next}
        end

      :error ->
        expr
        |> Enum.reduce({code_acc, expr, span_hoists, counter}, fn
          {key, value}, {acc_code, acc_expr, acc_hoists, acc_counter} ->
            {child_code, child_value, child_hoists, child_counter} =
              ensure_branch_span_hoists(value, refs_acc, acc_hoists, field_sources, acc_counter)

            {acc_code <> child_code, Map.put(acc_expr, key, child_value), child_hoists,
             child_counter}
        end)
        |> then(fn {c, e, h, ct} -> {c, e, h, ct} end)
    end
  end

  defp ensure_branch_span_hoists(expr, refs_acc, span_hoists, field_sources, counter, code_acc)
       when is_list(expr) do
    Enum.reduce(Enum.with_index(expr), {code_acc, [], span_hoists, counter}, fn
      {value, index}, {acc_code, acc_items, acc_hoists, acc_counter} ->
        {child_code, child_value, child_hoists, child_counter} =
          ensure_branch_span_hoists(value, refs_acc, acc_hoists, field_sources, acc_counter)

        {acc_code <> child_code, acc_items ++ [{index, child_value}], child_hoists, child_counter}
    end)
    |> then(fn {c, indexed, h, ct} ->
      {c, Enum.map(indexed, fn {_i, v} -> v end), h, ct}
    end)
  end

  defp ensure_branch_span_hoists(expr, _refs_acc, span_hoists, _field_sources, counter, code_acc),
    do: {code_acc, expr, span_hoists, counter}

  @doc false
  @spec debug_branch_span_mul_field(Types.ir_expr(), map(), map()) :: term()
  def debug_branch_span_mul_field(expr, refs_acc, field_sources),
    do: branch_span_mul_field(expr, refs_acc, field_sources)

  @doc false
  @spec debug_branch_span_key(Types.ir_expr(), map(), map()) :: term()
  def debug_branch_span_key(expr, refs_acc, field_sources),
    do: branch_span_key(expr, refs_acc, field_sources)

  defp branch_span_key(expr, refs_acc, field_sources) do
    case add_of_two_muls(expr) do
      {:ok, left_mul, right_mul} ->
        left = branch_span_mul_field(left_mul, refs_acc, field_sources)
        right = branch_span_mul_field(right_mul, refs_acc, field_sources)

        with {:ok, left_field, width} <- left,
             {:ok, right_field, gap} <- right,
             true <- left_field != right_field do
          {:ok, {left_field, width, right_field, gap}, left_field, width, right_field, gap}
        else
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp add_of_two_muls(%{op: :call, name: op, args: [left, right]})
       when op in ["__add__", "+"],
       do: {:ok, left, right}

  defp add_of_two_muls(%{op: :qualified_call, target: "Basics.add", args: [left, right]}),
    do: {:ok, left, right}

  defp add_of_two_muls(_), do: :error

  defp branch_span_mul_field(mul_expr, refs_acc, field_sources)

  defp branch_span_mul_field(
         %{op: :call, name: op, args: [%{op: :c_int_expr, value: ref}, %{op: :int_literal, value: width}]},
         refs_acc,
         _field_sources
       )
       when op in ["__mul__", "*"] and is_integer(width) do
    case field_for_ref(refs_acc, ref) do
      field when is_binary(field) -> {:ok, field, width}
      _ -> :error
    end
  end

  defp branch_span_mul_field(
         %{
           op: :qualified_call,
           target: op,
           args: [%{op: :c_int_expr, value: ref}, %{op: :int_literal, value: width}]
         },
         refs_acc,
         _field_sources
       )
       when op in ["Basics.mul", "*"] and is_integer(width) do
    case field_for_ref(refs_acc, ref) do
      field when is_binary(field) -> {:ok, field, width}
      _ -> :error
    end
  end

  defp branch_span_mul_field(
         %{
           op: :call,
           name: op,
           args: [%{op: :int_literal, value: gap_val}, %{op: :int_literal, value: scale}]
         },
         refs_acc,
         field_sources
       )
       when op in ["__mul__", "*"] and is_integer(scale) and is_integer(gap_val) do
    case field_for_literal_value(field_sources, refs_acc, gap_val) do
      field when is_binary(field) -> {:ok, field, scale}
      _ -> :error
    end
  end

  defp branch_span_mul_field(
         %{
           op: :qualified_call,
           target: op,
           args: [%{op: :int_literal, value: gap_val}, %{op: :int_literal, value: scale}]
         },
         refs_acc,
         field_sources
       )
       when op in ["Basics.mul", "*"] and is_integer(scale) and is_integer(gap_val) do
    case field_for_literal_value(field_sources, refs_acc, gap_val) do
      field when is_binary(field) -> {:ok, field, scale}
      _ -> :error
    end
  end

  defp branch_span_mul_field(
         %{op: :call, name: op, args: [left, %{op: :int_literal, value: scale}]},
         refs_acc,
         field_sources
       )
       when op in ["__mul__", "*"] and is_integer(scale) do
    branch_span_mul_field_named(left, refs_acc, field_sources, scale)
  end

  defp branch_span_mul_field(
         %{op: :qualified_call, target: op, args: [left, %{op: :int_literal, value: scale}]},
         refs_acc,
         field_sources
       )
       when op in ["Basics.mul", "*"] and is_integer(scale) do
    branch_span_mul_field_named(left, refs_acc, field_sources, scale)
  end

  defp branch_span_mul_field(
         %{op: :call, name: op, args: [%{op: :int_literal, value: width}, left]},
         refs_acc,
         field_sources
       )
       when op in ["__mul__", "*"] and is_integer(width) do
    branch_span_mul_field_named(left, refs_acc, field_sources, width)
  end

  defp branch_span_mul_field(
         %{
           op: :qualified_call,
           target: op,
           args: [%{op: :int_literal, value: width}, left]
         },
         refs_acc,
         field_sources
       )
       when op in ["Basics.mul", "*"] and is_integer(width) do
    branch_span_mul_field_named(left, refs_acc, field_sources, width)
  end

  defp branch_span_mul_field(_mul_expr, _refs_acc, _field_sources), do: :error

  defp branch_span_mul_field_named(left, refs_acc, _field_sources, scale) do
    case branch_span_field_name(left) do
      name when is_binary(name) ->
        if Map.has_key?(refs_acc, name), do: {:ok, name, scale}, else: :error

      _ ->
        case left do
          %{op: :c_int_expr, value: ref} ->
            case field_for_ref(refs_acc, ref) do
              field when is_binary(field) -> {:ok, field, scale}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp field_for_ref(refs_acc, ref) do
    Enum.find_value(refs_acc, fn {field, field_ref} ->
      if field_ref == ref, do: field
    end)
  end

  defp field_for_literal_value(field_sources, _refs_acc, value) do
    Enum.find_value(field_sources, fn {field, expr} ->
      if expr == %{op: :int_literal, value: value}, do: field
    end)
  end

  defp branch_span_ref(refs_acc, field_sources, field) do
    case Map.fetch(refs_acc, field) do
      {:ok, ref} ->
        ref

      :error ->
        case Map.fetch(field_sources, field) do
          {:ok, %{op: :int_literal, value: value}} -> Integer.to_string(value)
          _ -> Map.fetch!(refs_acc, field)
        end
    end
  end

  defp branch_span_field_name(%{op: :var, name: name}) when is_binary(name) or is_atom(name),
    do: EnvBindings.binding_key(name)

  defp branch_span_field_name(%{op: :call, name: name, args: []}) when is_binary(name), do: name

  defp branch_span_field_name(%{op: :qualified_call, target: target, args: []})
       when is_binary(target) do
    case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
      {_mod, name} -> name
      _ -> nil
    end
  end

  defp branch_span_field_name(_), do: nil

  defp rewrite_branch_value_hoists(expr, env) when is_map(expr) do
    case Host.hoisted_native_int_lookup(env, expr) do
      {:ok, ref} ->
        %{op: :c_int_expr, value: ref}

      :error ->
        expr
        |> Enum.map(fn
          {key, value} when is_map(value) or is_list(value) ->
            {key, rewrite_branch_value_hoists(value, env)}

          other ->
            other
        end)
        |> Map.new()
    end
  end

  defp rewrite_branch_value_hoists(expr, env) when is_list(expr),
    do: Enum.map(expr, &rewrite_branch_value_hoists(&1, env))

  defp rewrite_branch_value_hoists(expr, _env), do: expr

  defp register_branch_field_hoist?(%{op: :int_literal}), do: false
  defp register_branch_field_hoist?(%{op: :char_literal}), do: false
  defp register_branch_field_hoist?(%{op: :c_int_expr}), do: false
  defp register_branch_field_hoist?(_), do: true

  defp substitute_emitted_branch_field_calls_map(expr, field_map) do
    expr
    |> Map.new(fn
      {key, value} when is_list(value) ->
        {key, substitute_emitted_branch_field_calls(value, field_map)}

      {key, value} when is_map(value) ->
        {key, substitute_emitted_branch_field_calls(value, field_map)}

      {key, value} ->
        {key, value}
    end)
  end

  defp emit_field_entries(name, value_expr, field_entries, env, counter) do
    record_type =
      Expr.record_type_for_expr(value_expr, env) ||
        record_type_for_entries(field_entries, env) ||
        helper_record_type(value_expr, env)

    result =
      Enum.reduce_while(field_entries, {:ok, "", %{}, counter}, fn
        {_field, nil}, _acc ->
          {:halt, :error}

        {field, field_expr}, {:ok, code_acc, map_acc, c} ->
          case emit_native_record_field(name, field, field_expr, record_type, env, c) do
            {:ok, code, var, c2} ->
              {:cont, {:ok, code_acc <> code, Map.put(map_acc, field, var), c2}}

            :error ->
              {:halt, :error}
          end
      end)

    case result do
      {:ok, field_code, field_map, counter} ->
        field_code =
          maybe_extract_int_record_helper(
            name,
            value_expr,
            field_entries,
            record_type,
            env,
            field_code,
            field_map,
            counter
          )

        {:ok, field_code,
         put_native_record_binding(env, name, field_map, value_expr, field_entries), counter}

      :error ->
        :error
    end
  end

  defp maybe_extract_int_record_helper(
         name,
         value_expr,
         field_entries,
         record_type,
         env,
         field_code,
         field_map,
         counter
       ) do
    if extractable_int_record_helper?(field_entries, record_type, env, field_code) do
      case helper_params(value_expr, env) do
        {:ok, params} ->
          drop_hoists_declared_in_code(field_code)

          if length(field_entries) >= 2 do
            combined_int_record_helper(name, env, field_code, field_map, params, counter)
          else
            case per_field_int_record_helpers(
                   name,
                   field_entries,
                   record_type,
                   env,
                   field_map,
                   params,
                   counter
                 ) do
              nil ->
                combined_int_record_helper(name, env, field_code, field_map, params, counter)

              code ->
                code
            end
          end

        :error ->
          field_code
      end
    else
      field_code
    end
  end

  defp per_field_int_record_helpers(
         name,
         field_entries,
         record_type,
         env,
         field_map,
         params,
         counter
       ) do
    module_suffix = Util.safe_c_suffix(Map.get(env, :__module__, "Main"))
    name_suffix = Util.safe_c_suffix(name)
    helper_params = params |> helper_param_decls() |> Enum.join(", ")
    call_args = Enum.map_join(params, ", ", fn {_source, c_var} -> c_var end)

    result =
      field_entries
      |> Enum.with_index()
      |> Enum.reduce_while({[], []}, fn {{field, field_expr}, index}, {defs, calls} ->
        var = Map.fetch!(field_map, field)

        helper_name =
          "elmc_direct_native_record_#{module_suffix}_#{name_suffix}_#{Util.safe_c_suffix(field)}_#{counter}_#{index}"

        case emit_native_record_field_isolated(
               name,
               field,
               field_expr,
               record_type,
               env,
               counter + index + 1
             ) do
          {:ok, code, ref, _counter} ->
            helper_def = """
            static elmc_int_t #{helper_name}(#{helper_params}) {
            #{CSource.indent(code, 2)}
              return #{ref};
            }
            """

            call =
              if call_args == "" do
                "  elmc_int_t #{var} = #{helper_name}();"
              else
                "  elmc_int_t #{var} = #{helper_name}(#{call_args});"
              end

            {:cont, {[helper_def | defs], [call | calls]}}

          :error ->
            {:halt, :error}
        end
      end)

    case result do
      {defs, calls} ->
        Process.put(
          :elmc_direct_helper_defs,
          Enum.reverse(defs) ++ Process.get(:elmc_direct_helper_defs, [])
        )

        Enum.reverse(calls) |> Enum.join("\n")

      :error ->
        nil
    end
  end

  defp combined_int_record_helper(name, env, field_code, field_map, params, counter) do
    helper_name =
      "elmc_direct_native_record_#{Util.safe_c_suffix(Map.get(env, :__module__, "Main"))}_#{Util.safe_c_suffix(name)}_#{counter}"

    output_params =
      field_map
      |> Enum.sort_by(fn {field, _var} -> field end)
      |> Enum.map(fn {field, _var} ->
        "elmc_int_t * const out_#{Util.safe_c_suffix(field)}"
      end)

    param_decls = helper_param_decls(params)
    helper_params = Enum.join(param_decls ++ output_params, ", ")

    assignments =
      field_map
      |> Enum.sort_by(fn {field, _var} -> field end)
      |> Enum.map_join("\n  ", fn {field, var} ->
        "*out_#{Util.safe_c_suffix(field)} = #{var};"
      end)

    helper_def = """
    static void #{helper_name}(#{helper_params}) {
    #{CSource.indent(field_code, 2)}
      #{assignments}
    }
    """

    Process.put(
      :elmc_direct_helper_defs,
      [helper_def | Process.get(:elmc_direct_helper_defs, [])]
    )

    declarations =
      field_map
      |> Enum.sort_by(fn {field, _var} -> field end)
      |> Enum.map_join("\n", fn {_field, var} -> "  elmc_int_t #{var} = 0;" end)

    call_args =
      params
      |> Enum.map(fn {_source, c_var} -> c_var end)
      |> Kernel.++(
        field_map
        |> Enum.sort_by(fn {field, _var} -> field end)
        |> Enum.map(fn {_field, var} -> "&#{var}" end)
      )
      |> Enum.join(", ")

    """
    #{declarations}
      #{helper_name}(#{call_args});
    """
  end

  defp helper_param_decls(params) do
    Enum.map(params, fn {_source, c_var} -> "ElmcValue * const #{c_var}" end)
  end

  defp drop_hoists_declared_in_code(code) when is_binary(code) do
    declared_refs =
      ~r/const elmc_int_t (native_(?:min|max)_\d+) =/
      |> Regex.scan(code)
      |> Enum.map(&List.last/1)
      |> MapSet.new()

    if MapSet.size(declared_refs) > 0 do
      hoisted =
        :elmc_hoisted_native_ints
        |> Process.get(%{})
        |> Enum.reject(fn {_key, ref} -> MapSet.member?(declared_refs, ref) end)
        |> Map.new()

      Process.put(:elmc_hoisted_native_ints, hoisted)
    end

    :ok
  end

  defp emit_native_record_field_isolated(name, field, field_expr, record_type, env, counter) do
    hoisted_native_ints = Process.get(:elmc_hoisted_native_ints)

    try do
      Process.put(:elmc_hoisted_native_ints, %{})
      emit_native_record_field(name, field, field_expr, record_type, env, counter)
    after
      case hoisted_native_ints do
        nil -> Process.delete(:elmc_hoisted_native_ints)
        value -> Process.put(:elmc_hoisted_native_ints, value)
      end
    end
  end

  defp extractable_int_record_helper?(field_entries, record_type, env, field_code) do
    line_count = emitted_line_count(field_code)

    line_count >= 80 and
      (length(field_entries) >= 3 or line_count >= 160) and
      Enum.all?(field_entries, fn
        {_field, nil} ->
          false

        {field, field_expr} ->
          field_kind(record_type, field, field_expr, env) == "Int"
      end)
  end

  defp emitted_line_count(code) when is_binary(code), do: code |> String.split("\n") |> length()

  defp helper_params(value_expr, env) do
    vars =
      value_expr
      |> VarAnalysis.used_vars()
      |> Enum.sort()

    params =
      Enum.reduce_while(vars, [], fn var, acc ->
        case Map.get(env, var) do
          c_var when is_binary(c_var) -> {:cont, [{var, c_var} | acc]}
          _other -> {:halt, :error}
        end
      end)

    case params do
      :error -> :error
      params -> {:ok, Enum.reverse(params)}
    end
  end

  defp put_native_record_binding(env, name, field_map, value_expr, field_entries)
       when is_map(field_map) do
    type =
      Expr.record_type_for_expr(value_expr, env) ||
        Expr.record_type_for_field_names(Map.keys(field_map), env)

    field_names = native_record_shape_field_names(type, field_map, env)

    field_kinds = infer_field_kinds(field_entries, value_expr, env)

    env =
      env
      |> Map.put(name, {:native_record, field_map})
      |> EnvBindings.put_record_shape(name, field_names)
      |> put_record_field_kinds(name, field_kinds)

    if is_binary(type), do: EnvBindings.put_var_type(env, name, type), else: env
  end

  defp native_record_shape_field_names(type, field_map, env) when is_map(field_map) do
    case type && Expr.record_shape_for_type(type, env) do
      names when is_list(names) ->
        Enum.filter(names, &Map.has_key?(field_map, &1))

      _ ->
        field_map |> Map.keys() |> Enum.sort()
    end
  end

  defp put_record_field_kinds(env, _name, kinds) when map_size(kinds) == 0, do: env

  defp put_record_field_kinds(env, name, kinds) do
    all_kinds = Map.get(env, :__record_field_kinds__, %{})
    Map.put(env, :__record_field_kinds__, Map.put(all_kinds, name, kinds))
  end

  defp infer_field_kinds([], _value_expr, _env), do: %{}

  defp infer_field_kinds(field_entries, value_expr, env) when is_list(field_entries) do
    record_type =
      Expr.record_type_for_expr(value_expr, env) ||
        record_type_for_entries(field_entries, env) ||
        helper_record_type(value_expr, env)

    Map.new(field_entries, fn {field, field_expr} ->
      {field, field_kind(record_type, field, field_expr, env)}
    end)
  end

  defp record_type_for_entries(entries, env) do
    entries
    |> Enum.map(&elem(&1, 0))
    |> Expr.record_type_for_field_names(env)
  end

  defp native_record_field_expr?(field_expr, field, record_type, env) do
    case field_kind(record_type, field, field_expr, env) do
      "String" -> Host.native_string_expr?(field_expr, env)
      "Bool" -> Host.native_bool_expr?(field_expr, env)
      "Float" -> Host.native_float_expr?(field_expr, env)
      _ -> Host.native_int_expr?(field_expr, env)
    end
  end

  defp field_kind(record_type, field, field_expr, env) do
    case record_type do
      type when is_binary(type) ->
        RecordFields.lookup_field_type(type, field, env) ||
          inferred_field_type_from_expr(field_expr, env)

      _ ->
        inferred_field_type_from_expr(field_expr, env)
    end
  end

  defp inferred_field_type_from_expr(expr, env) do
    cond do
      match?(%{op: :string_literal}, expr) or Host.native_string_expr?(expr, env) ->
        "String"

      match?(%{op: :bool_literal}, expr) or Host.native_bool_expr?(expr, env) ->
        "Bool"

      match?(%{op: :float_literal}, expr) ->
        "Float"

      Host.native_int_expr?(expr, env) ->
        "Int"

      Host.native_float_expr?(expr, env) and not Host.native_int_expr?(expr, env) ->
        "Float"

      true ->
        "Int"
    end
  end

  defp emit_native_record_field(name, field, field_expr, record_type, env, counter) do
    kind = field_kind(record_type, field, field_expr, env)
    next = counter + 1
    var = "direct_native_record_#{Util.safe_c_suffix(name)}_#{field}_#{next}"

    case emit_native_field_value(field_expr, kind, var, env, counter) do
      {:ok, code, ref, c2} -> {:ok, code, ref, max(next, counter_after_emitted_code(code, c2))}
      :error -> :error
    end
  end

  defp emit_native_field_value(field_expr, kind, var, env, counter) do
    case kind do
      "String" ->
        if Host.native_string_expr?(field_expr, env) do
          {code, ref, _cleanup, c2} = Host.compile_native_string_expr(field_expr, env, counter)
          {:ok, scoped_field_value(code, "const char *", var, ref, "NULL"), var, c2}
        else
          :error
        end

      "Bool" ->
        if Host.native_bool_expr?(field_expr, env) do
          {code, ref, c2} = Host.compile_native_bool_expr(field_expr, env, counter)
          {:ok, scoped_field_value(code, "elmc_int_t", var, ref, "0"), var, c2}
        else
          :error
        end

      "Float" ->
        if Host.native_float_expr?(field_expr, env) do
          {code, ref, c2} = Host.compile_native_float_expr(field_expr, env, counter)
          {:ok, scoped_field_value(code, "double", var, ref, "0.0"), var, c2}
        else
          :error
        end

      _ ->
        {code, ref, c2} = Host.direct_int_value(field_expr, env, counter)
        {:ok, scoped_field_value(code, "elmc_int_t", var, ref, "0"), var, c2}
    end
  end

  defp scoped_field_value("", c_type, var, ref, _default) do
    direct_field_assign_decl(c_type, var, ref)
  end

  defp scoped_field_value(code, c_type, var, ref, _default) when is_binary(code) do
    {hoisted_code, scoped_code} = split_reusable_native_hoists(code)
    hoisted_code <> scoped_isolated_field_value(scoped_code, c_type, var, ref)
  end

  defp scoped_isolated_field_value(code, c_type, var, ref) do
    if String.trim(code) == "" do
      direct_field_assign_decl(c_type, var, ref)
    else
      """
        #{c_type} #{var};
        {
      #{CSource.indent(code, 4)}
          #{var} = #{ref};
        }
      """
    end
  end

  defp direct_field_assign_decl("const char *", var, ref) do
    "  const char *#{var} = #{ref};\n"
  end

  defp direct_field_assign_decl(c_type, var, ref) do
    "  const #{c_type} #{var} = #{ref};\n"
  end

  defp split_reusable_native_hoists(code) do
    lines = String.split(code, "\n", trim: false)
    {hoisted, scoped} = split_reusable_native_hoists(lines, [], [])

    if hoisted != [] do
      {Enum.reverse(hoisted) |> Enum.join("\n") |> then(&(&1 <> "\n")),
       Enum.reverse(scoped) |> Enum.join("\n")}
    else
      {"", code}
    end
  end

  defp split_reusable_native_hoists([], hoisted, scoped), do: {hoisted, scoped}

  defp split_reusable_native_hoists([line | rest], hoisted, scoped) do
    if reusable_native_hoist_decl?(line) do
      split_reusable_native_hoists(rest, [line | hoisted], scoped)
    else
      split_reusable_native_hoists(rest, hoisted, [line | scoped])
    end
  end

  defp reusable_native_hoist_decl?(line) do
    Regex.match?(
      ~r/^\s*const elmc_int_t native_(?:min|max)(?:_left|_right)?_\d+ = /,
      line
    ) and not Regex.match?(~r/\b(?:tmp|native_i|direct_i|__den|direct_den)_\d+\b/, line)
  end

  defp counter_after_emitted_code(code, counter) when is_binary(code) do
    code
    |> then(
      &Regex.scan(
        ~r/\b(?:tmp|native_i|native_b|native_if|native_min|native_max|direct_i|__den|direct_den)_(\d+)\b/,
        &1
      )
    )
    |> Enum.reduce(counter, fn [_match, suffix], acc ->
      case Integer.parse(suffix) do
        {n, ""} -> max(acc, n + 1)
        _ -> acc
      end
    end)
  end

  defp counter_after_emitted_code(_code, counter), do: counter
end
