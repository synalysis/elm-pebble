defmodule Elmc.Backend.CCodegen.DirectRender.Emit.MapLoops do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Release
  alias Elmc.Backend.CCodegen.DirectRender.ListLoopPlans
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @spec emit_indexed_map_loop(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.direct_emit_target(),
          boolean(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  def emit_indexed_map_loop(
         fun_expr,
         list_expr,
         {target_module, target_name, prefix_args},
         transparent?,
         env,
         counter
       ) do
    decl_map = Map.get(env, :__program_decls__, %{})

    target = {target_module, target_name, prefix_args}
    next = counter + 1
    c_name = if target_name, do: Util.module_fn_name(target_module, target_name), else: nil
    native_append? = not transparent? and indexed_map_native_append?(decl_map, target)
    arg_kinds = indexed_map_arg_kinds(decl_map, target)
    prefix_count = length(prefix_args)

    {prefix_code, prefix_refs, prefix_releases, native_prefix_fields, counter} =
      if transparent? or is_nil(target_name) do
        {"", [], [], nil, counter}
      else
        compile_indexed_map_prefix(
          prefix_args,
          Enum.take(arg_kinds, prefix_count),
          env,
          counter
        )
      end

    prefix_release_code = Release.release_vars(prefix_releases, "        ")

    case Host.direct_static_list_items(list_expr) do
      {:ok, static_items} ->
        if transparent? do
          case Host.direct_emit_static_render_items(static_items, env, counter) do
            {:ok, code, counter} -> {:ok, prefix_code <> code <> prefix_release_code, counter}
            :error -> :error
          end
        else
          case Host.direct_static_draw_table_loop(static_items, env, counter) do
            {:ok, table_code, counter} ->
              {:ok, prefix_code <> table_code <> prefix_release_code, counter}

            :error ->
              case Host.draw_affine_template_indexed(decl_map, target, env) do
                {:ok, spec, index_param, item_param} ->
                  Host.indexed_map_affine_draw_static_list_loop(
                    spec,
                    index_param,
                    item_param,
                    prefix_code,
                    prefix_refs,
                    native_prefix_fields,
                    prefix_release_code,
                    static_items,
                    next,
                    env,
                    counter
                  )

                :error ->
                  materialize_prefix_for_native_append(
                    native_append?,
                    prefix_code,
                    prefix_refs,
                    prefix_releases,
                    native_prefix_fields,
                    prefix_args,
                    prefix_release_code,
                    fn prefix_code, prefix_refs, prefix_release_code ->
                      indexed_map_static_list_loop(
                        native_append?,
                        prefix_code,
                        prefix_refs,
                        prefix_release_code,
                        static_items,
                        c_name,
                        next,
                        env,
                        counter
                      )
                    end,
                    env,
                    counter
                  )
              end
          end
        end

      :error when transparent? ->
        case Host.direct_range_bounds(list_expr, env, counter) do
          {:ok, range_code, first_ref, last_ref, counter} ->
            transparent_lambda_indexed_map_range_loop(
              fun_expr,
              range_code,
              first_ref,
              last_ref,
              env,
              counter
            )

          :error ->
            :error
        end

      :error ->
        case Host.direct_range_bounds(list_expr, env, counter) do
          {:ok, range_code, first_ref, last_ref, counter} ->
            case Host.draw_affine_template_indexed(decl_map, target, env) do
              {:ok, spec, index_param, item_param} ->
                Host.indexed_map_affine_draw_range_loop(
                  spec,
                  index_param,
                  item_param,
                  prefix_code,
                  prefix_refs,
                  native_prefix_fields,
                  prefix_release_code,
                  range_code,
                  first_ref,
                  last_ref,
                  next,
                  env,
                  counter
                )

              :error ->
                materialize_prefix_for_native_append(
                  native_append?,
                  prefix_code,
                  prefix_refs,
                  prefix_releases,
                  native_prefix_fields,
                  prefix_args,
                  prefix_release_code,
                  fn prefix_code, prefix_refs, prefix_release_code ->
                    indexed_map_range_loop(
                      native_append?,
                      prefix_code,
                      prefix_refs,
                      prefix_release_code,
                      range_code,
                      first_ref,
                      last_ref,
                      c_name,
                      next,
                      counter
                    )
                  end,
                  env,
                  counter
                )
            end

          :error ->
            case Host.draw_affine_template_indexed(decl_map, target, env) do
              {:ok, spec, index_param, item_param} ->
                Host.indexed_map_affine_draw_list_loop(
                  spec,
                  index_param,
                  item_param,
                  prefix_code,
                  prefix_refs,
                  native_prefix_fields,
                  prefix_release_code,
                  list_expr,
                  env,
                  counter
                )

              :error ->
                materialize_prefix_for_native_append(
                  native_append?,
                  prefix_code,
                  prefix_refs,
                  prefix_releases,
                  native_prefix_fields,
                  prefix_args,
                  prefix_release_code,
                  fn prefix_code, prefix_refs, prefix_release_code ->
                    indexed_map_list_loop(
                      native_append?,
                      prefix_code,
                      prefix_refs,
                      prefix_release_code,
                      list_expr,
                      c_name,
                      mapped_item_int?(decl_map, target, true),
                      next,
                      env,
                      counter
                    )
                  end,
                  env,
                  counter
                )
            end
        end
    end
  end

  @spec transparent_lambda_map_range_loop(
          Types.expr(),
          String.t(),
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp transparent_lambda_map_range_loop(
         %{op: :lambda, args: [arg_name], body: body},
         range_code,
         first_ref,
         last_ref,
         env,
         counter
       ) do
    next = counter + 1
    item_var = "direct_item_i_#{next}"

    body_env =
      env
      |> Map.delete(arg_name)
      |> EnvBindings.put_native_int_binding(arg_name, item_var)
      |> EnvBindings.put_boxed_int_binding(arg_name, false)

    emit_loop_body(body, body_env, next, fn body_code, counter ->
      {:ok,
       """
       #{range_code}
         elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
         for (elmc_int_t #{item_var} = #{first_ref}; Rc == RC_SUCCESS; #{item_var} += direct_step_#{next}) {
       #{CSource.indent(body_code, 2)}
           if (#{item_var} == #{last_ref}) break;
         }
       """, counter}
    end)
  end

  defp transparent_lambda_map_range_loop(_fun_expr, _range_code, _first_ref, _last_ref, _env, _counter),
    do: :error

  @spec transparent_lambda_indexed_map_range_loop(
          Types.expr(),
          String.t(),
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp transparent_lambda_indexed_map_range_loop(
         %{op: :lambda, args: [index_name, item_name], body: body},
         range_code,
         first_ref,
         last_ref,
         env,
         counter
       ) do
    next = counter + 1
    index_var = "direct_index_#{next}"
    item_var = "direct_item_i_#{next}"

    body_env =
      env
      |> Map.delete(index_name)
      |> Map.delete(item_name)
      |> EnvBindings.put_native_int_binding(index_name, index_var)
      |> EnvBindings.put_native_int_binding(item_name, item_var)
      |> EnvBindings.put_boxed_int_binding(index_name, false)
      |> EnvBindings.put_boxed_int_binding(item_name, false)

    emit_loop_body(body, body_env, next, fn body_code, counter ->
      {:ok,
       """
       #{range_code}
         elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
         for (elmc_int_t #{item_var} = #{first_ref}, #{index_var} = 0; Rc == RC_SUCCESS; #{item_var} += direct_step_#{next}, #{index_var} += 1) {
       #{CSource.indent(body_code, 2)}
           if (#{item_var} == #{last_ref}) break;
         }
       """, counter}
    end)
  end

  defp transparent_lambda_indexed_map_range_loop(
         %{op: :lambda, args: [item_name], body: body},
         range_code,
         first_ref,
         last_ref,
         env,
         counter
       ) do
    transparent_lambda_map_range_loop(
      %{op: :lambda, args: [item_name], body: body},
      range_code,
      first_ref,
      last_ref,
      env,
      counter
    )
  end

  defp transparent_lambda_indexed_map_range_loop(_fun_expr, _range_code, _first_ref, _last_ref, _env, _counter),
    do: :error

  @spec emit_map_loop(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.direct_emit_target(),
          boolean(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def emit_map_loop(
         fun_expr,
         list_expr,
         {target_module, target_name, prefix_args},
         transparent?,
         env,
         counter
       ) do
    decl_map = Map.get(env, :__program_decls__, %{})
    target = {target_module, target_name, prefix_args}
    next = counter + 1
    c_name = if target_name, do: Util.module_fn_name(target_module, target_name), else: nil
    native_append? = not transparent? and map_native_append?(decl_map, target)
    arg_kinds = map_arg_kinds(decl_map, target)
    prefix_count = length(prefix_args)

    {prefix_code, prefix_refs, prefix_releases, _native_prefix_fields, counter} =
      if transparent? or is_nil(target_name) do
        {"", [], [], nil, counter}
      else
        compile_indexed_map_prefix(
          prefix_args,
          Enum.take(arg_kinds, prefix_count),
          env,
          counter
        )
      end

    prefix_release_code = Release.release_vars(prefix_releases, "        ")

    cond do
      transparent? ->
        emit_map_loop_transparent(
          fun_expr,
          list_expr,
          prefix_code,
          prefix_release_code,
          env,
          counter
        )

      true ->
        case ListLoopPlans.analyze(list_expr, env) do
          {:ok, plans} ->
            if ListLoopPlans.fusion_plans?(plans) do
              ListLoopPlans.emit_map_loops(
                plans,
                {target_module, target_name, prefix_args},
                prefix_code,
                prefix_refs,
                prefix_release_code,
                env,
                counter
              )
            else
              emit_map_loop_default(
                fun_expr,
                list_expr,
                {target_module, target_name, prefix_args},
                prefix_code,
                prefix_refs,
                prefix_release_code,
                native_append?,
                c_name,
                next,
                env,
                counter,
                decl_map
              )
            end

          :error ->
            emit_map_loop_default(
              fun_expr,
              list_expr,
              {target_module, target_name, prefix_args},
              prefix_code,
              prefix_refs,
              prefix_release_code,
              native_append?,
              c_name,
              next,
              env,
              counter,
              decl_map
            )
        end
    end
  end

  @spec emit_map_loop_transparent(
          Types.expr(),
          Types.expr(),
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp emit_map_loop_transparent(fun_expr, list_expr, prefix_code, prefix_release_code, env, counter) do
    case Host.direct_static_list_items(list_expr) do
      {:ok, static_items} ->
        case Host.direct_emit_static_render_items(static_items, env, counter) do
          {:ok, code, counter} -> {:ok, prefix_code <> code <> prefix_release_code, counter}
          :error -> :error
        end

      :error ->
        case Host.direct_range_bounds(list_expr, env, counter) do
          {:ok, range_code, first_ref, last_ref, counter} ->
            case transparent_lambda_map_range_loop(fun_expr, range_code, first_ref, last_ref, env, counter) do
              {:ok, body_code, counter} ->
                {:ok, prefix_code <> body_code <> prefix_release_code, counter}

              :error ->
                :error
            end

          :error ->
            :error
        end
    end
  end

  @spec emit_map_loop_default(
          Types.expr(),
          Types.expr(),
          Types.direct_emit_target(),
          String.t(),
          [String.t()],
          String.t(),
          boolean(),
          String.t() | nil,
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter(),
          Types.decl_map()
        ) :: Types.direct_emit_result()

  defp emit_map_loop_default(
         _fun_expr,
         list_expr,
         target,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         native_append?,
         c_name,
         next,
         env,
         counter,
         decl_map
       ) do
    {target_module, target_name, prefix_args} = target

    case Host.direct_static_list_items(list_expr) do
      {:ok, static_items} ->
        case Host.direct_static_draw_table_loop(static_items, env, counter) do
          {:ok, table_code, counter} ->
            {:ok, prefix_code <> table_code <> prefix_release_code, counter}

          :error ->
            map_static_list_loop(
              native_append?,
              prefix_code,
              prefix_refs,
              prefix_release_code,
              static_items,
              c_name,
              next,
              env,
              counter
            )
        end

      :error ->
        item_param =
          case Map.get(decl_map, {target_module, target_name}) do
            %{args: args} when is_list(args) ->
              Enum.at(args, length(prefix_args)) || "direct_item"

            _ ->
              "direct_item"
          end

        case Host.direct_range_bounds(list_expr, env, counter) do
          {:ok, range_code, first_ref, last_ref, counter} ->
            case Host.draw_affine_template(decl_map, target, item_param, env) do
              {:ok, spec} ->
                Host.map_affine_draw_range_loop(
                  spec,
                  prefix_code,
                  prefix_release_code,
                  range_code,
                  first_ref,
                  last_ref,
                  next,
                  env,
                  counter
                )

              :error ->
                map_range_loop(
                  native_append?,
                  prefix_code,
                  prefix_refs,
                  prefix_release_code,
                  range_code,
                  first_ref,
                  last_ref,
                  c_name,
                  next,
                  counter
                )
            end

          :error ->
            case Host.draw_affine_template(decl_map, target, item_param, env) do
              {:ok, spec} ->
                Host.map_affine_draw_list_loop(
                  spec,
                  prefix_code,
                  prefix_release_code,
                  list_expr,
                  env,
                  counter
                )

              :error ->
                map_list_loop(
                  native_append?,
                  prefix_code,
                  prefix_refs,
                  prefix_release_code,
                  list_expr,
                  c_name,
                  mapped_item_int?(decl_map, target, false),
                  next,
                  env,
                  counter
                )
            end
        end
    end
  end

  @spec indexed_map_range_loop(
          boolean(),
          String.t(),
          [String.t()],
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp indexed_map_range_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         range_code,
         first_ref,
         last_ref,
         c_name,
         next,
         counter
       ) do
    arg_list =
      Enum.join(prefix_refs ++ ["direct_index_#{next}", "direct_item_i_#{next}"], ", ")

    {:ok,
     """
     #{prefix_code}
     #{range_code}
      elmc_int_t direct_index_#{next} = 0;
      elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
         #{Catch.assign_command_append("#{c_name}_commands_append_native(#{arg_list}, writer)", prefix_release_code)}
         if (direct_item_i_#{next} == #{last_ref}) break;
         direct_index_#{next} += 1;
       }
     #{prefix_release_code}
     """, counter}
  end

  defp indexed_map_range_loop(
         false,
         prefix_code,
         prefix_vars,
         prefix_release_code,
         range_code,
         first_ref,
         last_ref,
         c_name,
         next,
         counter
       ) do
    prefix_count = length(prefix_vars)

    prefix_bindings =
      prefix_vars
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {var, index} ->
        "      direct_call_args_#{next}[#{index}] = #{var};"
      end)

    {:ok,
     """
     #{prefix_code}
     #{range_code}
      elmc_int_t direct_index_#{next} = 0;
      elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
        #{RcRuntimeEmit.check_rc_take("direct_index_value_#{next}", "elmc_new_int", "direct_index_#{next}", RcRuntimeEmit.rc_catch_env(%{}))}
        #{RcRuntimeEmit.check_rc_take("direct_item_value_#{next}", "elmc_new_int", "direct_item_i_#{next}", RcRuntimeEmit.rc_catch_env(%{}))}
         ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
     #{prefix_bindings}
         direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
         direct_call_args_#{next}[#{prefix_count + 1}] = direct_item_value_#{next};
         elmc_release(direct_index_value_#{next});
         elmc_release(direct_item_value_#{next});
         #{Catch.assign_command_append("#{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, writer)", prefix_release_code)}
         if (direct_item_i_#{next} == #{last_ref}) break;
         direct_index_#{next} += 1;
       }
     #{prefix_release_code}
     """, counter}
  end

  @spec indexed_map_list_loop(
          boolean(),
          String.t(),
          [String.t()],
          String.t(),
          Types.expr(),
          String.t(),
          boolean(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp indexed_map_list_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         list_expr,
         c_name,
         _int_items?,
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(list_expr, env, counter)

    head_native = "direct_native_head_#{next}"

    arg_list =
      Enum.join(
        prefix_refs ++
          ["direct_index_#{next}", head_native],
        ", "
      )

    loop_body = """
           #{Catch.assign_command_append("#{c_name}_commands_append_native(#{arg_list}, writer)", "#{Release.release_var(list_var, "             ")}\n#{prefix_release_code}")}
    """

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     #{direct_list_walk_native_int_head(list_var, next, true, loop_body)}
     #{Release.release_var(list_var, "     ")}
     #{prefix_release_code}
     """, counter}
  end

  defp indexed_map_list_loop(
         false,
         prefix_code,
         prefix_vars,
         prefix_release_code,
         list_expr,
         c_name,
         int_items?,
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(list_expr, env, counter)
    prefix_count = length(prefix_vars)

    {prefix_setup_code, prefix_slots, prefix_boxed_release_code, counter} =
      boxed_prefix_call_args(prefix_vars, next, counter)

    prefix_arg_bindings =
      prefix_slots
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {slot, index} ->
        "      direct_call_args_#{next}[#{index}] = #{slot};"
      end)

    loop_prefix_release_code = prefix_release_code <> prefix_boxed_release_code
    arg_count = prefix_count + 2

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     #{prefix_setup_code}
     #{direct_list_walk_indexed_boxed_head(list_var, next, prefix_count, prefix_arg_bindings, arg_count, c_name, loop_prefix_release_code, int_items?)}
     #{Release.release_var(list_var, "     ")}
     #{loop_prefix_release_code}
     """, counter}
  end


  @spec compile_arg_values([Types.expr()], Types.compile_env(), Types.compile_counter()) ::
          {String.t(), [String.t()], Types.compile_counter()}

  defp compile_arg_values(args, env, counter) do
    Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
      {code, var, c2} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(arg_expr, env, c)
      {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
    end)
  end

  @spec compile_mixed_arg_values(
          [Types.expr()],
          [Types.direct_command_arg_kind()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], [String.t()], Types.compile_counter()}

  defp compile_mixed_arg_values(args, kinds, env, counter) do
    args
    |> Enum.zip(kinds)
    |> Enum.reduce({"", [], [], counter}, fn {arg_expr, kind},
                                              {code_acc, refs_acc, releases_acc, c} ->
      case kind do
        :native_int ->
          {code, ref, c2} = Host.compile_native_int_expr(arg_expr, env, c)
          {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

        :native_string ->
          {code, ref, cleanup, c2} = Host.compile_native_string_expr(arg_expr, env, c)
          {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ cleanup, c2}

        :boxed ->
          {code, ref, c2} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(arg_expr, env, c)
          {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ [ref], c2}
      end
    end)
  end

  @spec compile_indexed_map_prefix(
          [Types.expr()],
          [Types.direct_command_arg_kind()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], [String.t()], map() | nil, Types.compile_counter()}

  defp compile_indexed_map_prefix(prefix_args, arg_kinds, env, counter) do
    case {prefix_args, arg_kinds} do
      {[%{op: :var, name: name}], [:boxed]} ->
        case Map.get(env, name) do
          {:native_record, native_fields} ->
            {prefix_code, prefix_refs, prefix_releases, counter} =
              {"", [], [], counter}

            {prefix_code, prefix_refs, prefix_releases, native_fields, counter}

          _ ->
            {prefix_code, prefix_refs, prefix_releases, counter} =
              compile_mixed_arg_values(prefix_args, arg_kinds, env, counter)

            {prefix_code, prefix_refs, prefix_releases, nil, counter}
        end

      {[%{op: :var, name: name} | rest_args], [_ | rest_kinds]} when rest_args != [] ->
        case Map.get(env, name) do
          {:native_record, native_fields} ->
            {prefix_code, prefix_refs, prefix_releases, counter} =
              if Enum.any?(rest_kinds, &(&1 != :boxed)) do
                compile_mixed_arg_values(rest_args, rest_kinds, env, counter)
              else
                {code, refs, c} = compile_arg_values(rest_args, env, counter)
                {code, refs, [], c}
              end

            {prefix_code, prefix_refs, prefix_releases, native_fields, counter}

          _ ->
            compile_indexed_map_prefix_fallback(prefix_args, arg_kinds, env, counter)
        end

      _ ->
        compile_indexed_map_prefix_fallback(prefix_args, arg_kinds, env, counter)
    end
  end

  @spec compile_indexed_map_prefix_fallback(
          [Types.expr()],
          [Types.direct_command_arg_kind()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], [String.t()], map() | nil, Types.compile_counter()}

  defp compile_indexed_map_prefix_fallback(prefix_args, arg_kinds, env, counter) do
    case {prefix_args, arg_kinds} do
      _ ->
        if Enum.any?(arg_kinds, &(&1 != :boxed)) do
          {prefix_code, prefix_refs, prefix_releases, counter} =
            compile_mixed_arg_values(prefix_args, arg_kinds, env, counter)

          {prefix_code, prefix_refs, prefix_releases, nil, counter}
        else
          {prefix_code, prefix_refs, counter} =
            compile_arg_values(prefix_args, env, counter)

          {prefix_code, prefix_refs, [], nil, counter}
        end
    end
  end

  @spec materialize_prefix_for_native_append(
          boolean(),
          String.t(),
          [String.t()],
          [String.t()],
          map() | nil,
          [Types.expr()],
          String.t(),
          (String.t(), [String.t()], String.t() -> Types.direct_emit_result()),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp materialize_prefix_for_native_append(
         false,
         prefix_code,
         prefix_refs,
         _prefix_releases,
         _native_prefix_fields,
         _prefix_args,
         prefix_release_code,
         emit_fallback,
         _env,
         _counter
       ) do
    emit_fallback.(prefix_code, prefix_refs, prefix_release_code)
  end

  defp materialize_prefix_for_native_append(
         true,
         prefix_code,
         prefix_refs,
         prefix_releases,
         native_prefix_fields,
         prefix_args,
         _prefix_release_code,
         emit_fallback,
         env,
         counter
       ) do
    {prefix_code, prefix_refs, prefix_releases, _counter} =
      maybe_materialize_native_prefix_refs(
        prefix_code,
        prefix_refs,
        prefix_releases,
        native_prefix_fields,
        prefix_args,
        env,
        counter
      )

    prefix_release_code = Release.release_vars(prefix_releases, "        ")
    emit_fallback.(prefix_code, prefix_refs, prefix_release_code)
  end

  @spec maybe_materialize_native_prefix_refs(
          String.t(),
          [String.t()],
          [String.t()],
          map() | nil,
          [Types.expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], [String.t()], Types.compile_counter()}

  defp maybe_materialize_native_prefix_refs(
         prefix_code,
         prefix_refs,
         prefix_releases,
         native_fields,
         prefix_args,
         env,
         counter
       )
       when is_binary(prefix_code) and is_list(prefix_refs) and is_list(prefix_releases) and
              is_list(prefix_args) and is_map(env) and is_integer(counter) do
    cond do
      prefix_refs != [] ->
        {prefix_code, prefix_refs, prefix_releases, counter}

      not is_map(native_fields) or map_size(native_fields) == 0 ->
        {prefix_code, prefix_refs, prefix_releases, counter}

      true ->
        materialize_native_prefix_refs(
          prefix_code,
          prefix_releases,
          native_fields,
          prefix_args,
          env,
          counter
        )
    end
  end

  @spec materialize_native_prefix_refs(
          String.t(),
          [String.t()],
          map(),
          [Types.expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), [String.t()], [String.t()], Types.compile_counter()}

  defp materialize_native_prefix_refs(
         prefix_code,
         prefix_releases,
         native_fields,
         prefix_args,
         env,
         counter
       ) do
    layout_name = prefix_layout_binding_name(prefix_args)
    field_names = native_prefix_field_names(layout_name, native_fields, env)
    layout_var = "direct_prefix_layout_#{counter + 1}"
    next = counter + 1
    rec_suffix = Elmc.Backend.CCodegen.RecordCompile.fresh_rec_values_suffix()
    count = length(field_names)

    values_array =
      field_names
      |> Enum.map_join(", ", fn field -> Map.fetch!(native_fields, field) end)

    code = """
    #{prefix_code}
    elmc_int_t rec_values_#{rec_suffix}[#{count}] = { #{values_array} };
    #{ValueSlots.boxed_decl(layout_var, "elmc_record_new_values_ints(#{count}, rec_values_#{rec_suffix})", env)}
    """

    {code, [layout_var], prefix_releases ++ [layout_var], next}
  end

  @spec prefix_layout_binding_name([Types.expr()] | term()) :: String.t()

  defp prefix_layout_binding_name([%{op: :var, name: name} | _]) when not is_nil(name),
    do: EnvBindings.binding_key(name)

  defp prefix_layout_binding_name(_prefix_args), do: "layout"

  @spec native_prefix_field_names(String.t(), map(), Types.compile_env()) :: [String.t()]

  defp native_prefix_field_names(layout_name, native_fields, env) do
    shapes = Map.get(env, :__record_shapes__, %{})

    case Map.get(shapes, layout_name) do
      names when is_list(names) ->
        Enum.filter(names, &Map.has_key?(native_fields, &1))

      _ ->
        native_fields
        |> Map.keys()
        |> Enum.map(&to_string/1)
    end
  end

  @spec indexed_map_native_append?(Types.decl_map(), term()) :: boolean()

  defp indexed_map_native_append?(decl_map, {target_module, target_name, prefix_args}) do
    with %{type: _} = decl <- Map.get(decl_map, {target_module, target_name}),
         kinds <- CommandDef.arg_kinds(decl),
         prefix_count <- length(prefix_args),
         index_kind when index_kind == :native_int <- Enum.at(kinds, prefix_count),
         item_kind when item_kind == :native_int <- Enum.at(kinds, prefix_count + 1) do
      true
    else
      _ -> false
    end
  end

  @spec indexed_map_arg_kinds(Types.decl_map(), term()) :: [Types.direct_command_arg_kind()]

  defp indexed_map_arg_kinds(decl_map, {target_module, target_name, _prefix_args}) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{type: _} = decl -> CommandDef.arg_kinds(decl)
      _ -> []
    end
  end

  @spec map_native_append?(Types.decl_map(), term()) :: boolean()

  defp map_native_append?(decl_map, {target_module, target_name, prefix_args}) do
    with %{type: _} = decl <- Map.get(decl_map, {target_module, target_name}),
         kinds <- CommandDef.arg_kinds(decl),
         prefix_count <- length(prefix_args),
         item_kind when item_kind == :native_int <- Enum.at(kinds, prefix_count) do
      true
    else
      _ -> false
    end
  end

  # Compact INT_LIST walks only apply to `List Int`. Record/string maps must not
  # emit that backend — it is dead code and dominates analog `List.map` scenes.
  defp mapped_item_int?(decl_map, {target_module, target_name, prefix_args}, indexed?) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{type: _} = decl ->
        idx = length(List.wrap(prefix_args)) + if(indexed?, do: 1, else: 0)

        case Enum.at(CommandDef.arg_kinds(decl), idx) do
          :native_int -> true
          nil -> true
          _ -> false
        end

      _ ->
        true
    end
  end

  @spec map_arg_kinds(Types.decl_map(), term()) :: [Types.direct_command_arg_kind()]

  defp map_arg_kinds(decl_map, {target_module, target_name, _prefix_args}) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{type: _} = decl -> CommandDef.arg_kinds(decl)
      _ -> []
    end
  end

  @spec map_range_loop(
          boolean(),
          String.t(),
          [String.t()],
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp map_range_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         range_code,
         first_ref,
         last_ref,
         c_name,
         next,
         counter
       ) do
    arg_list = Enum.join(prefix_refs ++ ["direct_item_i_#{next}"], ", ")

    {:ok,
     """
     #{prefix_code}
     #{range_code}
      elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
         #{Catch.assign_command_append("#{c_name}_commands_append_native(#{arg_list}, writer)", prefix_release_code)}
         if (direct_item_i_#{next} == #{last_ref}) break;
       }
     #{prefix_release_code}
     """, counter}
  end

  defp map_range_loop(
         false,
         prefix_code,
         prefix_vars,
         prefix_release_code,
         range_code,
         first_ref,
         last_ref,
         c_name,
         next,
         counter
       ) do
    prefix_count = length(prefix_vars)

    prefix_bindings =
      prefix_vars
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {var, index} ->
        "      direct_call_args_#{next}[#{index}] = #{var};"
      end)

    {:ok,
     """
     #{prefix_code}
     #{range_code}
      elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
         #{RcRuntimeEmit.check_rc_take("direct_item_value_#{next}", "elmc_new_int", "direct_item_i_#{next}", RcRuntimeEmit.rc_catch_env(%{}))}
         ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
     #{prefix_bindings}
         direct_call_args_#{next}[#{prefix_count}] = direct_item_value_#{next};
         elmc_release(direct_item_value_#{next});
         #{Catch.assign_command_append("#{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, writer)", prefix_release_code)}
         if (direct_item_i_#{next} == #{last_ref}) break;
       }
     #{prefix_release_code}
     """, counter}
  end

  @spec map_list_loop(
          boolean(),
          String.t(),
          [String.t()],
          String.t(),
          Types.expr(),
          String.t(),
          boolean(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp map_list_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         list_expr,
         c_name,
         _int_items?,
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(list_expr, env, counter)

    head_native = "direct_native_head_#{next}"

    arg_list =
      Enum.join(prefix_refs ++ [head_native], ", ")

    loop_body = """
           #{Catch.assign_command_append("#{c_name}_commands_append_native(#{arg_list}, writer)", "#{Release.release_var(list_var, "             ")}\n#{prefix_release_code}")}
    """

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     #{direct_list_walk_native_int_head(list_var, next, false, loop_body)}
     #{Release.release_var(list_var, "     ")}
     #{prefix_release_code}
     """, counter}
  end

  defp map_list_loop(
         false,
         prefix_code,
         prefix_vars,
         prefix_release_code,
         list_expr,
         c_name,
         int_items?,
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(list_expr, env, counter)
    prefix_count = length(prefix_vars)

    {prefix_setup_code, prefix_slots, prefix_boxed_release_code, counter} =
      boxed_prefix_call_args(prefix_vars, next, counter)

    prefix_arg_bindings =
      prefix_slots
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {slot, index} ->
        "      direct_call_args_#{next}[#{index}] = #{slot};"
      end)

    loop_prefix_release_code = prefix_release_code <> prefix_boxed_release_code
    arg_count = prefix_count + 1

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     #{prefix_setup_code}
     #{direct_list_walk_boxed_head(list_var, next, prefix_count, prefix_arg_bindings, arg_count, c_name, loop_prefix_release_code, int_items?)}
     #{Release.release_var(list_var, "     ")}
     #{loop_prefix_release_code}
     """, counter}
  end

  @spec map_static_list_loop(
          boolean(),
          String.t(),
          [String.t()],
          String.t(),
          [Types.expr()],
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp map_static_list_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         items,
         c_name,
         _next,
         _env,
         counter
       ) do
    body =
      items
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {_item, index} ->
        arg_list = Enum.join(prefix_refs ++ ["#{index}"], ", ")

        """
          #{Catch.assign_command_append("#{c_name}_commands_append_native(#{arg_list}, writer)", prefix_release_code)}
        """
      end)

    {:ok, prefix_code <> body <> prefix_release_code, counter}
  end

  defp map_static_list_loop(
         false,
         prefix_code,
         prefix_vars,
         prefix_release_code,
         items,
         c_name,
         next,
         env,
         counter
       ) do
    prefix_count = length(prefix_vars)

    prefix_bindings =
      prefix_vars
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {var, index} ->
        "      direct_call_args_#{next}[#{index}] = #{var};"
      end)

    {body, counter} =
      Enum.reduce(items, {"", counter}, fn item, {acc, c} ->
        {item_code, item_var, c2} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(item, env, c)

        snippet = """
        #{item_code}
          ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
        #{prefix_bindings}
          direct_call_args_#{next}[#{prefix_count}] = #{item_var};
          Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, writer);
          #{Release.release_var(item_var, "          ")}
          #{Catch.check_rc(prefix_release_code)}
        """

        {acc <> snippet, c2}
      end)

    {:ok, prefix_code <> body <> prefix_release_code, counter}
  end

  @spec indexed_map_static_list_loop(
          boolean(),
          String.t(),
          [String.t()],
          String.t(),
          [Types.expr()],
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  defp indexed_map_static_list_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         items,
         c_name,
         _next,
         _env,
         counter
       ) do
    body =
      items
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {_item, index} ->
        arg_list = Enum.join(prefix_refs ++ ["#{index}", "#{index}"], ", ")

        """
          #{Catch.assign_command_append("#{c_name}_commands_append_native(#{arg_list}, writer)", prefix_release_code)}
        """
      end)

    {:ok, prefix_code <> body <> prefix_release_code, counter}
  end

  defp indexed_map_static_list_loop(
         false,
         prefix_code,
         prefix_vars,
         prefix_release_code,
         items,
         c_name,
         next,
         env,
         counter
       ) do
    prefix_count = length(prefix_vars)

    prefix_bindings =
      prefix_vars
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {var, index} ->
        "      direct_call_args_#{next}[#{index}] = #{var};"
      end)

    {body, counter} =
      Enum.reduce(Enum.with_index(items), {"", counter}, fn {item, index}, {acc, c} ->
        {item_code, item_var, c2} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(item, env, c)
        index_var = "direct_static_index_#{c2}"
        next_c = c2 + 1

        snippet = """
        #{item_code}
          ElmcValue *#{index_var} = NULL;
          #{RcRuntimeEmit.check_rc_take(index_var, "elmc_new_int", index, RcRuntimeEmit.rc_catch_env(%{}))}
          ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
        #{prefix_bindings}
          direct_call_args_#{next}[#{prefix_count}] = #{index_var};
          direct_call_args_#{next}[#{prefix_count + 1}] = #{item_var};
          Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, writer);
          #{Release.release_var(index_var, "          ")}
          #{Release.release_var(item_var, "          ")}
          #{Catch.check_rc(prefix_release_code)}
        """

        {acc <> snippet, next_c}
      end)

    {:ok, prefix_code <> body <> prefix_release_code, counter}
  end


  @spec emit_lambda_map(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def emit_lambda_map(arg, body, list_expr, env, counter) do
    next = counter + 1

    case Host.direct_range_bounds(list_expr, env, counter) do
      {:ok, range_code, first_ref, last_ref, counter} ->
        item_ref = "direct_item_i_#{next}"

        body_env =
          env
          |> Map.delete(arg)
          |> EnvBindings.put_native_int_binding(arg, item_ref)
          |> EnvBindings.put_boxed_int_binding(arg, false)

        emit_loop_body(body, body_env, counter, fn body_code, counter ->
          {:ok,
           """
           #{range_code}
            elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
            for (elmc_int_t direct_item_i_#{next} = #{first_ref}; Rc == RC_SUCCESS; direct_item_i_#{next} += direct_step_#{next}) {
           #{CSource.indent(body_code, 4)}
               if (direct_item_i_#{next} == #{last_ref}) break;
             }
           """, counter}
        end)

      :error ->
        {list_code, list_var, counter} = Elmc.Backend.CCodegen.DirectRender.Emit.Operand.compile(list_expr, env, counter)
        item_var = "direct_node_#{next}->head"
        body_env = Map.put(env, arg, item_var)

        emit_loop_body(body, body_env, counter, fn body_code, counter ->
          item_boxed = "direct_il_item_#{next}"

          body_env_int =
            env
            |> Map.delete(arg)
            |> Map.put(arg, item_boxed)

          emit_loop_body(body, body_env_int, counter, fn body_code_int, counter ->
            {:ok,
             """
             #{list_code}
             #{direct_list_walk_lambda_body(list_var, next, item_boxed, body_code, body_code_int)}
             #{Release.release_var(list_var, "             ")}
             """, counter}
          end)
        end)
    end
  end

  @spec emit_loop_body(
          Types.expr(),
          Types.compile_env(),
          Types.compile_counter(),
          (String.t(), Types.compile_counter() -> Types.direct_emit_result())
        ) :: Types.direct_emit_result()

  defp emit_loop_body(body, body_env, counter, builder) when is_function(builder, 2) do
    ValueSlots.push_loop()

    try do
      case Host.direct_emit_expr(body, body_env, counter) do
        {:ok, body_code, counter} -> builder.(body_code, counter)
        :error -> :error
      end
    after
      ValueSlots.pop_loop()
    end
  end

  @spec boxed_prefix_call_args([String.t()], non_neg_integer(), Types.compile_counter()) ::
          {String.t(), [String.t()], String.t(), Types.compile_counter()}

  defp boxed_prefix_call_args(prefix_vars, loop_id, counter) do
    Enum.reduce(prefix_vars, {"", [], "", counter}, fn var, {setup_acc, slots_acc, release_acc, c} ->
      if boxed_elmc_value_ref?(var) do
        {setup_acc, slots_acc ++ [var], release_acc, c}
      else
        next = c + 1
        boxed = "direct_prefix_boxed_#{loop_id}_#{next}"
        catch_env = RcRuntimeEmit.rc_catch_env(%{})

        setup =
          setup_acc <>
            "  #{RcRuntimeEmit.check_rc_take(boxed, "elmc_new_int", var, catch_env)};\n"

        release =
          release_acc <> Release.release_vars([boxed], "        ")

        {setup, slots_acc ++ [boxed], release, next}
      end
    end)
    |> then(fn {setup, slots, release, c} -> {setup, slots, release, c} end)
  end

  @spec boxed_elmc_value_ref?(String.t() | term()) :: boolean()

  defp boxed_elmc_value_ref?(ref) when is_binary(ref) do
    Regex.match?(
      ~r/^(tmp_\d+|owned\[\d+\]|model|elmc_|direct_node_|direct_cursor_|direct_item_|direct_index_)/,
      ref
    )
  end

  defp boxed_elmc_value_ref?(_), do: false

  @spec direct_list_walk_native_int_head(String.t(), non_neg_integer(), boolean(), String.t()) ::
          String.t()

  defp direct_list_walk_native_int_head(list_var, next, indexed?, loop_body)
       when is_binary(list_var) and is_binary(loop_body) do
    head = "direct_native_head_#{next}"
    index_decl = if indexed?, do: "  elmc_int_t direct_index_#{next} = 0;\n", else: ""
    index_inc = if indexed?, do: "      direct_index_#{next} += 1;\n", else: ""

    """
    #{index_decl}if (#{list_var} && #{list_var}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *direct_ilp_#{next} = (ElmcIntListPayload *)#{list_var}->payload;
      int direct_ilen_#{next} = direct_ilp_#{next} ? direct_ilp_#{next}->length : 0;
      for (int direct_ii_#{next} = 0; Rc == RC_SUCCESS && direct_ii_#{next} < direct_ilen_#{next}; direct_ii_#{next}++) {
        const elmc_int_t #{head} = direct_ilp_#{next}->values[direct_ii_#{next}];
    #{loop_body}
    #{index_inc}
      }
    } else {
      ElmcValue *direct_cursor_#{next} = #{list_var};
    #{if indexed?, do: "  elmc_int_t direct_index_#{next} = 0;\n", else: ""}
      while (Rc == RC_SUCCESS && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
        ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
        const elmc_int_t #{head} = elmc_as_int(direct_node_#{next}->head);
    #{loop_body}
    #{index_inc}
        direct_cursor_#{next} = direct_node_#{next}->tail;
      }
    }
    """
  end

  @spec direct_list_walk_indexed_boxed_head(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          boolean()
        ) :: String.t()

  defp direct_list_walk_indexed_boxed_head(
         list_var,
         next,
         prefix_count,
         prefix_bindings,
         arg_count,
         c_name,
         loop_prefix_release_code,
         int_items?
       ) do
    record_seq_prefix =
      direct_record_seq_boxed_head_loop(
        list_var,
        next,
        prefix_count,
        prefix_bindings,
        arg_count,
        c_name,
        loop_prefix_release_code,
        true
      )

    int_list_branch =
      if int_items? do
        """
         if (#{list_var} && #{list_var}->tag == ELMC_TAG_INT_LIST) {
          ElmcIntListPayload *direct_ilp_#{next} = (ElmcIntListPayload *)#{list_var}->payload;
          int direct_ilen_#{next} = direct_ilp_#{next} ? direct_ilp_#{next}->length : 0;
          elmc_int_t direct_index_#{next} = 0;
          for (int direct_ii_#{next} = 0; Rc == RC_SUCCESS && direct_ii_#{next} < direct_ilen_#{next}; direct_ii_#{next}++) {
            #{RcRuntimeEmit.check_rc_take("direct_index_value_#{next}", "elmc_new_int", "direct_index_#{next}", RcRuntimeEmit.rc_catch_env(%{}))}
            #{RcRuntimeEmit.check_rc_take("direct_item_value_#{next}", "elmc_new_int", "direct_ilp_#{next}->values[direct_ii_#{next}]", RcRuntimeEmit.rc_catch_env(%{}))}
            ElmcValue *direct_call_args_#{next}[#{max(arg_count, 1)}] = {0};
        #{prefix_bindings}
            direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
            direct_call_args_#{next}[#{prefix_count + 1}] = direct_item_value_#{next};
            elmc_release(direct_index_value_#{next});
            elmc_release(direct_item_value_#{next});
            Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{arg_count}, writer);
            #{Catch.check_rc("#{Release.release_var(list_var, "     ")}\n#{loop_prefix_release_code}")}
            direct_index_#{next} += 1;
          }
        } else
        """
      else
        ""
      end

    """
    #{record_seq_prefix}#{int_list_branch} {
      ElmcValue *direct_cursor_#{next} = #{list_var};
      elmc_int_t direct_index_#{next} = 0;
      while (Rc == RC_SUCCESS && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
        ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
        #{RcRuntimeEmit.check_rc_take("direct_index_value_#{next}", "elmc_new_int", "direct_index_#{next}", RcRuntimeEmit.rc_catch_env(%{}))}
        ElmcValue *direct_call_args_#{next}[#{max(arg_count, 1)}] = {0};
    #{prefix_bindings}
        direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
        direct_call_args_#{next}[#{prefix_count + 1}] = direct_node_#{next}->head;
        elmc_release(direct_index_value_#{next});
        Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{arg_count}, writer);
        #{Catch.check_rc("#{Release.release_var(list_var, "     ")}\n#{loop_prefix_release_code}")}
        direct_index_#{next} += 1;
        direct_cursor_#{next} = direct_node_#{next}->tail;
      }
    }
    """
  end

  @spec direct_record_seq_boxed_head_loop(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          boolean()
        ) :: String.t()

  defp direct_record_seq_boxed_head_loop(
         list_var,
         next,
         prefix_count,
         prefix_bindings,
         arg_count,
         c_name,
         loop_prefix_release_code,
         indexed?
       ) do
    index_decl = if indexed?, do: "      elmc_int_t direct_index_#{next} = 0;\n", else: ""
    index_arg =
      if indexed? do
        """
              #{RcRuntimeEmit.check_rc_take("direct_index_value_#{next}", "elmc_new_int", "direct_index_#{next}", RcRuntimeEmit.rc_catch_env(%{}))}
        """
      else
        ""
      end

    index_release = if indexed?, do: "        elmc_release(direct_index_value_#{next});\n", else: ""
    index_inc = if indexed?, do: "        direct_index_#{next} += 1;\n", else: ""
    item_arg_index = if indexed?, do: prefix_count + 1, else: prefix_count

    index_binding =
      if indexed? do
        "        direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};\n"
      else
        ""
      end

    """
    #{index_decl}if (#{list_var} && #{list_var}->tag == ELMC_TAG_RECORD_SEQ) {
      int direct_rlen_#{next} = elmc_record_seq_length(#{list_var});
      for (int direct_ii_#{next} = 0; Rc == RC_SUCCESS && direct_ii_#{next} < direct_rlen_#{next}; direct_ii_#{next}++) {
    #{index_arg}        ElmcValue *direct_item_value_#{next} = elmc_record_seq_get(#{list_var}, direct_ii_#{next});
        ElmcValue *direct_call_args_#{next}[#{max(arg_count, 1)}] = {0};
    #{prefix_bindings}
    #{index_binding}        direct_call_args_#{next}[#{item_arg_index}] = direct_item_value_#{next};
        Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{arg_count}, writer);
    #{index_release}        elmc_release(direct_item_value_#{next});
        #{Catch.check_rc("#{Release.release_var(list_var, "     ")}\n#{loop_prefix_release_code}")}
    #{index_inc}      }
    } else
    """
  end

  @spec direct_list_walk_boxed_head(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          boolean()
        ) :: String.t()

  defp direct_list_walk_boxed_head(
         list_var,
         next,
         prefix_count,
         prefix_bindings,
         arg_count,
         c_name,
         loop_prefix_release_code,
         int_items?
       ) do
    record_seq_prefix =
      direct_record_seq_boxed_head_loop(
        list_var,
        next,
        prefix_count,
        prefix_bindings,
        arg_count,
        c_name,
        loop_prefix_release_code,
        false
      )

    int_list_branch =
      if int_items? do
        """
         else if (#{list_var} && #{list_var}->tag == ELMC_TAG_INT_LIST) {
          ElmcIntListPayload *direct_ilp_#{next} = (ElmcIntListPayload *)#{list_var}->payload;
          int direct_ilen_#{next} = direct_ilp_#{next} ? direct_ilp_#{next}->length : 0;
          for (int direct_ii_#{next} = 0; Rc == RC_SUCCESS && direct_ii_#{next} < direct_ilen_#{next}; direct_ii_#{next}++) {
            #{RcRuntimeEmit.check_rc_take("direct_item_value_#{next}", "elmc_new_int", "direct_ilp_#{next}->values[direct_ii_#{next}]", RcRuntimeEmit.rc_catch_env(%{}))}
            ElmcValue *direct_call_args_#{next}[#{max(arg_count, 1)}] = {0};
        #{prefix_bindings}
            direct_call_args_#{next}[#{prefix_count}] = direct_item_value_#{next};
            Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{arg_count}, writer);
            elmc_release(direct_item_value_#{next});
            #{Catch.check_rc("#{Release.release_var(list_var, "     ")}\n#{loop_prefix_release_code}")}
          }
        }
        """
      else
        ""
      end

    """
    #{record_seq_prefix} if (#{list_var} && #{list_var}->tag == ELMC_TAG_LAZY_MAP) {
      int direct_llen_#{next} = elmc_lazy_map_length(#{list_var});
      for (int direct_ii_#{next} = 0; Rc == RC_SUCCESS && direct_ii_#{next} < direct_llen_#{next}; direct_ii_#{next}++) {
        ElmcValue *direct_item_value_#{next} = NULL;
        Rc = elmc_lazy_map_nth(&direct_item_value_#{next}, #{list_var}, direct_ii_#{next});
        CHECK_RC(Rc);
        ElmcValue *direct_call_args_#{next}[#{max(arg_count, 1)}] = {0};
    #{prefix_bindings}
        direct_call_args_#{next}[#{prefix_count}] = direct_item_value_#{next};
        Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{arg_count}, writer);
        elmc_release(direct_item_value_#{next});
        #{Catch.check_rc("#{Release.release_var(list_var, "     ")}\n#{loop_prefix_release_code}")}
      }
    }#{int_list_branch} else {
      ElmcValue *direct_cursor_#{next} = #{list_var};
      while (Rc == RC_SUCCESS && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
        ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
        ElmcValue *direct_call_args_#{next}[#{max(arg_count, 1)}] = {0};
    #{prefix_bindings}
        direct_call_args_#{next}[#{prefix_count}] = direct_node_#{next}->head;
        Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{arg_count}, writer);
        #{Catch.check_rc("#{Release.release_var(list_var, "     ")}\n#{loop_prefix_release_code}")}
        direct_cursor_#{next} = direct_node_#{next}->tail;
      }
    }
    """
  end

  @spec direct_list_walk_lambda_body(
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()

  defp direct_list_walk_lambda_body(list_var, next, item_boxed, cons_body, int_body) do
    int_item_decl =
      RcRuntimeEmit.check_rc_take(
        item_boxed,
        "elmc_new_int",
        "direct_ilp_#{next}->values[direct_ii_#{next}]",
        RcRuntimeEmit.rc_catch_env(%{})
      )

    int_item_release = Release.release_var(item_boxed, "        ")

    """
    if (#{list_var} && #{list_var}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *direct_ilp_#{next} = (ElmcIntListPayload *)#{list_var}->payload;
      int direct_ilen_#{next} = direct_ilp_#{next} ? direct_ilp_#{next}->length : 0;
      for (int direct_ii_#{next} = 0; Rc == RC_SUCCESS && direct_ii_#{next} < direct_ilen_#{next}; direct_ii_#{next}++) {
        #{int_item_decl}
    #{CSource.indent(int_body, 4)}
        #{int_item_release}
      }
    } else {
      ElmcValue *direct_cursor_#{next} = #{list_var};
      while (Rc == RC_SUCCESS && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
        ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
    #{CSource.indent(cons_body, 4)}
        direct_cursor_#{next} = direct_node_#{next}->tail;
      }
    }
    """
  end
end
