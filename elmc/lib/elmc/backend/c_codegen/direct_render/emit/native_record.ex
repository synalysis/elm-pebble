defmodule Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions
  alias Elmc.Backend.CCodegen.DirectRender.UseSites
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.RecordFields
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
    [{_field, %{op: :direct_native_if, cond: cond}} | _] = field_entries

    record_type =
      Expr.record_type_for_expr(value_expr, env) ||
        record_type_for_entries(field_entries, env) ||
        helper_record_type(value_expr, env)

    {cond_code, cond_ref, cond_cleanup, counter} =
      if Host.native_bool_expr?(cond, env) do
        {code, ref, c} = Host.compile_native_bool_expr(cond, env, counter)
        {code, ref, "", c}
      else
        {code, var, c} = Host.compile_expr(cond, env, counter)
        {code, "elmc_as_int(#{var}) != 0", "  elmc_release(#{var});\n", c}
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

            merge_code = branch_merge_decl(kind, var, cond_ref, then_ref, else_ref)
            {code_acc <> merge_code, Map.put(map_acc, field, var), next}
        end)

      body_env =
        env
        |> put_native_record_binding(name, field_map, value_expr, then_entries ++ else_entries)
        |> Hoist.put_hoisted_native_bool(cond, cond_ref)
        |> Hoist.merge_process_hoisted_native_ints()

      {:ok, cond_code <> cond_cleanup <> then_code <> else_code <> field_code, body_env, counter}
    else
      :error -> :error
    end
  end

  defp emit_branch_fields(_branch, [], _record_type, _env, counter),
    do: {:ok, "", %{}, %{}, counter}

  defp emit_branch_fields(branch, field_entries, record_type, env, counter) do
    env = Hoist.merge_process_hoisted_native_ints(env)
    field_entries = sort_branch_field_entries(field_entries)

    result =
      Enum.reduce_while(field_entries, {:ok, "", %{}, %{}, counter}, fn
        {field, field_expr}, {:ok, code_acc, refs_acc, kinds_acc, c} ->
          field_expr = substitute_emitted_branch_field_calls(field_expr, refs_acc)
          kind = field_kind(record_type, field, field_expr, env)
          var = "direct_native_record_branch_#{branch}_#{field}_#{c}"

          case emit_native_field_value(field_expr, kind, var, env, c) do
            {:ok, code, ref, c2} ->
              {:cont,
               {:ok, code_acc <> code, Map.put(refs_acc, field, ref),
                Map.put(kinds_acc, field, kind), c2}}

            :error ->
              {:halt, :error}
          end
      end)

    case result do
      {:ok, code, refs, kinds, counter} -> {:ok, code, refs, kinds, counter}
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

  defp sort_branch_field_entries(field_entries) do
    names = MapSet.new(Enum.map(field_entries, &elem(&1, 0)))

    deps =
      Map.new(field_entries, fn {field, expr} ->
        {field,
         branch_field_zero_arg_call_deps(expr, names, []) |> Enum.uniq() |> List.delete(field)}
      end)

    sort_branch_field_entries_by_deps(field_entries, deps, [])
  end

  defp sort_branch_field_entries_by_deps([], _deps, acc), do: Enum.reverse(acc)

  defp sort_branch_field_entries_by_deps(remaining, deps, acc) do
    ready =
      Enum.filter(remaining, fn {field, _} ->
        Enum.all?(Map.get(deps, field, []), &(&1 in acc))
      end)

    case ready do
      [] -> Enum.reverse(acc) ++ remaining
      _ -> sort_branch_field_entries_by_deps(remaining -- ready, deps, acc ++ ready)
    end
  end

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
              drop_hoists_declared_in_code(field_code)
              combined_int_record_helper(name, env, field_code, field_map, params, counter)

            code ->
              drop_hoists_declared_in_code(field_code)
              code
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
            #{Util.indent(code, 2)}
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
    #{Util.indent(field_code, 2)}
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
    field_names = field_map |> Map.keys() |> Enum.sort()

    field_kinds = infer_field_kinds(field_entries, value_expr, env)

    env =
      env
      |> Map.put(name, {:native_record, field_map})
      |> EnvBindings.put_record_shape(name, field_names)
      |> put_record_field_kinds(name, field_kinds)

    type =
      Expr.record_type_for_expr(value_expr, env) ||
        Expr.record_type_for_field_names(field_names, env)

    if is_binary(type), do: EnvBindings.put_var_type(env, name, type), else: env
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
        case Host.direct_int_value(field_expr, env, counter) do
          {code, ref, c2} -> {:ok, scoped_field_value(code, "elmc_int_t", var, ref, "0"), var, c2}
          :error -> :error
        end
    end
  end

  defp scoped_field_value("", c_type, var, ref, default) do
    "  #{c_type} #{var} = #{default};\n  #{var} = #{ref};\n"
  end

  defp scoped_field_value(code, c_type, var, ref, _default) when is_binary(code) do
    {hoisted_code, scoped_code} = split_reusable_native_hoists(code)
    hoisted_code <> scoped_isolated_field_value(scoped_code, c_type, var, ref)
  end

  defp scoped_isolated_field_value(code, c_type, var, ref) do
    default =
      case c_type do
        "const char *" -> "NULL"
        "double" -> "0.0"
        _ -> "0"
      end

    """
      #{c_type} #{var} = #{default};
      {
    #{Util.indent(code, 4)}
        #{var} = #{ref};
      }
    """
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
