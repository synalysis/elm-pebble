defmodule Elmc.Backend.CCodegen.TailRecursiveLoopEmit do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Operand
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @spec compile_fusion(
          Types.decl(),
          String.t(),
          Types.compile_env(),
          [atom()],
          atom()
        ) :: {:ok, String.t(), String.t()} | :error
  def compile_fusion(decl, module_name, env, arg_kinds, return_kind)
      when return_kind in [:boxed, :native_int, :native_bool] and is_list(arg_kinds) do
    c_arg_bindings = FunctionEmit.c_arg_bindings(decl.args || [])
    compile(decl, module_name, env, c_arg_bindings, arg_kinds, return_kind)
  end

  @spec compile(
          Types.decl(),
          String.t(),
          Types.compile_env(),
          [Types.c_arg_binding()],
          [atom()],
          atom()
        ) :: {:ok, String.t(), String.t()} | :error
  def compile(decl, module_name, env, arg_bindings, arg_kinds, return_kind) do
    arg_names = decl.args || []
    arg_types = if is_binary(decl.type), do: TypeParsing.function_arg_types(decl.type), else: []

    with true <- arg_names != [],
         true <- tail_recursive_arg_kinds?(arg_kinds, arg_types),
         {:if_tail, cond_expr, base_expr, recursive_args, recurse_on_truthy?, let_prelude} <-
           tail_recursive_if(decl.expr, module_name, decl.name),
         true <- length(recursive_args) == length(arg_names) do
      c_arg_bindings =
        case arg_bindings do
          bindings when bindings != [] -> bindings
          _ -> FunctionEmit.c_arg_bindings(arg_names)
        end

      loop_bindings =
        c_arg_bindings
        |> Enum.with_index()
        |> Enum.zip(arg_kinds)
        |> Enum.map_join("\n  ", fn {{{_arg, c_arg, _index}, index}, kind} ->
          loop = loop_arg_name(c_arg)

          case {kind, Enum.at(arg_types, index) |> TypeParsing.normalize_type_name()} do
            {:native_int, _} ->
              "elmc_int_t #{loop} = #{c_arg};"

            {:boxed, "Int"} ->
              "elmc_int_t #{loop} = elmc_as_int(#{c_arg});"

            {:native_bool, _} ->
              "bool #{loop} = #{c_arg};"

            {:boxed, _} ->
              "ElmcValue *#{loop} = #{c_arg} ? elmc_retain(#{c_arg}) : elmc_int_zero();"

            _ ->
              "elmc_int_t #{loop} = #{c_arg};"
          end
        end)

      loop_env =
        c_arg_bindings
        |> Enum.with_index()
        |> Enum.zip(arg_kinds)
        |> Enum.reduce(env, fn {{{source_arg, c_arg, _index}, index}, kind}, acc ->
          loop = loop_arg_name(c_arg)

          case {kind, Enum.at(arg_types, index) |> TypeParsing.normalize_type_name()} do
            {:native_int, _} ->
              EnvBindings.put_native_int_binding(acc, source_arg, loop)

            {:boxed, "Int"} ->
              EnvBindings.put_native_int_binding(acc, source_arg, loop)

            {:native_bool, _} ->
              EnvBindings.put_native_bool_binding(acc, source_arg, loop)

            {:boxed, _} ->
              Map.put(acc, source_arg, loop)

            _ ->
              acc
          end
        end)

      {hoist_code, loop_env, counter, hoisted_refs} =
        hoist_tail_recursive_top_level_vars(
          recursive_args,
          let_prelude,
          loop_env,
          0,
          module_name
        )

      loop_env =
        loop_env
        |> Map.put(:__tail_loop_invariant_refs__, MapSet.new(hoisted_refs))
        |> direct_render_env()

      ValueSlots.push_loop()

      {cond_code, cond_ref, counter} = NativeBool.compile_expr(cond_expr, loop_env, counter)

      {base_code, base_ref, counter} =
        if return_kind == :boxed do
          Operand.compile(base_expr, loop_env, counter)
        else
          compile_scalar_native_expr(base_expr, loop_env, return_kind, counter)
        end

      {update_code, int_update_refs, boxed_update_refs, boxed_int_refresh_refs, _loop_env} =
        compile_tail_recursive_continue_updates(
          recursive_args,
          c_arg_bindings,
          arg_kinds,
          arg_types,
          loop_env,
          counter,
          let_prelude
        )

      result_var = "tail_result"

      continue_branch =
        tail_continue_branch(
          update_code,
          int_update_refs,
          boxed_update_refs,
          boxed_int_refresh_refs,
          loop_env
        )

      base_branch =
        if return_kind == :boxed do
          tail_base_branch_boxed(
            base_code,
            result_var,
            base_ref,
            c_arg_bindings,
            arg_kinds,
            arg_types
          )
        else
          tail_base_branch(base_code, result_var, base_ref)
        end

      {then_branch, else_branch} =
        if recurse_on_truthy?,
          do: {continue_branch, base_branch},
          else: {base_branch, continue_branch}

      ValueSlots.pop_loop()

      result_decl =
        if return_kind == :boxed,
          do: "ElmcValue *#{result_var} = NULL;",
          else: "elmc_int_t #{result_var} = 0;"

      code = """
      #{loop_bindings}
      #{hoist_code}
        #{result_decl}
        while (1) {
      #{CSource.indent(cond_code, 4)}
          if (#{cond_ref}) {
      #{CSource.indent(then_branch, 6)}
          } else {
      #{CSource.indent(else_branch, 6)}
          }
        }
      """

      _ = module_name
      {:ok, code, result_var}
    else
      _ -> :error
    end
  end

  defp direct_render_env(env) do
    Map.put_new(env, :__direct_render_emit__, true)
  end

  defp compile_scalar_native_expr(expr, env, :native_int, counter),
    do: NativeInt.compile_expr(expr, env, counter)

  defp compile_scalar_native_expr(expr, env, :native_bool, counter),
    do: NativeBool.compile_expr(expr, env, counter)

  defp compile_tail_recursive_continue_updates(
         recursive_args,
         c_arg_bindings,
         arg_kinds,
         arg_types,
         loop_env,
         counter,
         let_prelude
       ) do
    {loop_env, counter, let_code} =
      Enum.reduce(let_prelude, {loop_env, counter, ""}, fn {let_name, let_value},
                                                            {env, ctr, code_acc} ->
        {let_code, let_ref, ctr2} =
          case NativeInt.compile_expr(let_value, env, ctr) do
            {_, ref, _} = native_result ->
              if native_int_loop_let_ref?(ref),
                do: native_result,
                else: Operand.compile(let_value, env, ctr)
          end

        env =
          if native_int_loop_let_ref?(let_ref) do
            env
            |> Map.put(let_name, let_ref)
            |> EnvBindings.put_native_int_binding(let_name, let_ref)
          else
            Map.put(env, let_name, let_ref)
          end

        {env, ctr2, code_acc <> "\n" <> let_code}
      end)

    {_counter, update_code, int_refs, boxed_refs, boxed_int_refs} =
      recursive_args
      |> Enum.zip(c_arg_bindings)
      |> Enum.zip(arg_kinds)
      |> Enum.with_index()
      |> Enum.reduce({counter, let_code, [], [], []}, fn {{{arg_expr, {_source_arg, c_arg, _index}}, kind}, index},
                                                    {ctr, code_acc, int_refs, boxed_refs, boxed_int_refs} ->
        loop = loop_arg_name(c_arg)
        type_name = Enum.at(arg_types, index) |> TypeParsing.normalize_type_name()
        loop_kind = effective_tail_loop_kind(kind, type_name)

        {arg_code, arg_ref, ctr2} =
          compile_tail_recursive_step_arg(arg_expr, loop_env, loop_kind, ctr)

        case loop_kind do
          :boxed ->
            {ctr2, code_acc <> "\n" <> arg_code, int_refs, boxed_refs ++ [{loop, arg_ref}],
             boxed_int_refs}

          _ ->
            next_ref = "#{loop}_next"

            {ctr2,
             code_acc <> "\n" <> arg_code <> "\n      elmc_int_t #{next_ref} = #{arg_ref};",
             int_refs ++ [{loop, next_ref}], boxed_refs, boxed_int_refs}
        end
      end)

    {update_code, int_refs, boxed_refs, boxed_int_refs, loop_env}
  end

  defp effective_tail_loop_kind(:boxed, "Int"), do: :native_int
  defp effective_tail_loop_kind(kind, _type_name), do: kind

  defp native_int_loop_let_ref?(ref) when is_binary(ref) do
    not Regex.match?(~r/^(owned|tmp)_\d+$/, ref) and
      not Regex.match?(~r/^native_i_\d+$/, ref) and
      (String.starts_with?(ref, "native_") or String.starts_with?(ref, "(") or
         Regex.match?(~r/^[a-z_]*_loop(?:_next)?$/, ref))
  end

  defp compile_tail_recursive_step_arg(expr, loop_env, :boxed, counter),
    do: Operand.compile(expr, loop_env, counter)

  defp compile_tail_recursive_step_arg(expr, loop_env, :native_bool, counter),
    do: NativeBool.compile_expr(expr, loop_env, counter)

  defp compile_tail_recursive_step_arg(expr, loop_env, :native_int, counter),
    do: NativeInt.compile_expr(expr, loop_env, counter)

  defp hoist_tail_recursive_top_level_vars(recursive_args, let_prelude, env, counter, module_name) do
    vars =
      recursive_args
      |> Enum.flat_map(&collect_ir_var_names/1)
      |> Enum.concat(Enum.flat_map(let_prelude, fn {_name, value} -> collect_ir_var_names(value) end))
      |> Enum.uniq()
      |> Enum.filter(fn name ->
        not Map.has_key?(env, name) and
          match?(
            %{args: args} when is_list(args),
            Map.get(Map.get(env, :__program_decls__, %{}), {module_name, name})
          ) and
          EnvBindings.function_arity(env, module_name, name, []) == 0
      end)

    Enum.reduce(vars, {"", env, counter, []}, fn name, {code_acc, env_acc, ctr, refs_acc} ->
      {var_code, ref, ctr2} = FunctionCallCompile.compile_var(name, env_acc, ctr)

      refs_acc =
        if ValueSlots.owned_ref?(ref) do
          [ref | refs_acc]
        else
          refs_acc
        end

      {code_acc <> var_code <> "\n", Map.put(env_acc, name, ref), ctr2, refs_acc}
    end)
  end

  defp collect_ir_var_names(%{op: :var, name: name}) when is_binary(name), do: [name]

  defp collect_ir_var_names(map) when is_map(map) do
    map |> Map.values() |> Enum.flat_map(&collect_ir_var_names/1)
  end

  defp collect_ir_var_names(list) when is_list(list) do
    Enum.flat_map(list, &collect_ir_var_names/1)
  end

  defp collect_ir_var_names(_), do: []

  defp tail_recursive_if(
         %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr},
         module_name,
         name
       ) do
    case tail_recursive_branch(then_expr, module_name, name) do
      {:tail, args, let_prelude} ->
        {:if_tail, cond, else_expr, args, true, let_prelude}

      :error ->
        case tail_recursive_branch(else_expr, module_name, name) do
          {:tail, args, let_prelude} ->
            {:if_tail, cond, then_expr, args, false, let_prelude}

          :error ->
            :error
        end
    end
  end

  defp tail_recursive_if(_expr, _module_name, _name), do: :error

  defp tail_recursive_branch(expr, module_name, name) do
    {let_prelude, core} = peel_tail_recursive_lets(expr, [])

    if Util.local_function_call?(core, module_name, name) do
      {:tail, core.args || [], let_prelude}
    else
      :error
    end
  end

  defp peel_tail_recursive_lets(
         %{op: :let_in, name: let_name, value_expr: let_value, in_expr: in_expr},
         acc
       ) do
    peel_tail_recursive_lets(in_expr, acc ++ [{let_name, let_value}])
  end

  defp peel_tail_recursive_lets(expr, acc), do: {acc, expr}

  defp tail_recursive_arg_kinds?(arg_kinds, arg_types) do
    arg_kinds
    |> Enum.with_index()
    |> Enum.all?(fn {kind, index} ->
      case {kind, Enum.at(arg_types, index) |> TypeParsing.normalize_type_name()} do
        {:native_int, _} -> true
        {:native_bool, _} -> true
        {:boxed, _} -> true
        _ -> false
      end
    end)
  end

  defp loop_arg_name(c_arg), do: "#{c_arg}_loop"

  defp tail_loop_caller_rc?(env) do
    Map.get(env, :__rc_catch__, false) or Map.get(env, :__rc_required__, false) or
      Map.get(env, :__native_rc_out__, false)
  end

  defp tail_int_box_new_stmt(box, loop, env) do
    if tail_loop_caller_rc?(env) do
      "Rc = elmc_new_int(&#{box}, #{loop});\n  CHECK_RC(Rc);"
    else
      """
      {
        RC __box_rc = elmc_new_int(&#{box}, #{loop});
        if (__box_rc != RC_SUCCESS) {
          ELMC_RC_LOG_FAIL(__box_rc, "elmc_new_int", "allocation failed");
          return 0;
        }
      }
      """
      |> String.trim()
    end
  end

  defp tail_continue_branch(
         update_code,
         int_update_refs,
         boxed_update_refs,
         boxed_int_refresh_refs,
         env
       ) do
    int_assignments =
      int_update_refs
      |> Enum.map_join("\n      ", fn {target, next_ref} -> "#{target} = #{next_ref};" end)

    boxed_int_refresh =
      boxed_int_refresh_refs
      |> Enum.map_join("\n      ", fn {box, loop} ->
        "elmc_release(#{box});\n      #{box} = NULL;\n      #{tail_int_box_new_stmt(box, loop, env)}"
      end)

    boxed_releases =
      boxed_update_refs
      |> Enum.map_join("\n      ", fn {loop, _ref} -> "elmc_release(#{loop});" end)

    boxed_assignments =
      boxed_update_refs
      |> Enum.map_join("\n      ", fn {loop, ref} ->
        if ValueSlots.owned_ref?(ref) do
          """
          #{loop} = #{ref};
          #{ValueSlots.transfer_and_null(ref)}
          """
        else
          "#{loop} = #{ref};"
        end
      end)

    """
    #{update_code}
      #{boxed_releases}
      #{int_assignments}
      #{boxed_int_refresh}
      #{boxed_assignments}
      continue;
    """
  end

  defp tail_base_branch_boxed(base_code, result_var, base_ref, arg_bindings, arg_kinds, arg_types) do
    loop_boxed_names =
      arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{{_source, c_arg, _arg_index}, kind}, index} ->
        type_name = Enum.at(arg_types, index) |> TypeParsing.normalize_type_name()

        cond do
          effective_tail_loop_kind(kind, type_name) == :boxed ->
            [loop_arg_name(c_arg)]

          true ->
            []
        end
      end)

    {result_assign, skip_release} =
      cond do
        ValueSlots.owned_ref?(base_ref) ->
          {"""
           #{result_var} = #{base_ref};
           #{ValueSlots.transfer_and_null(base_ref)}
           """, MapSet.new()}

        base_ref in loop_boxed_names ->
          {"#{result_var} = #{base_ref};\n      #{base_ref} = NULL;", MapSet.new([base_ref])}

        true ->
          {"#{result_var} = #{base_ref};", MapSet.new()}
      end

    releases =
      loop_boxed_names
      |> Enum.reject(&MapSet.member?(skip_release, &1))
      |> Enum.map_join("\n      ", fn name -> "elmc_release(#{name});" end)

    """
    #{base_code}
      #{result_assign}
      #{releases}
      break;
    """
  end

  defp tail_base_branch(base_code, result_var, base_ref) do
    """
    #{base_code}
      #{result_var} = #{base_ref};
      break;
    """
  end
end
