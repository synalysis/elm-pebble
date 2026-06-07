defmodule Elmc.Backend.CCodegen.DirectRender.Emit.MapLoops do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Release
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

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
                indexed_map_list_loop(
                  native_append?,
                  prefix_code,
                  prefix_refs,
                  prefix_release_code,
                  list_expr,
                  c_name,
                  next,
                  env,
                  counter
                )
            end
        end
    end
  end

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

    case Host.direct_emit_expr(body, body_env, next) do
      {:ok, body_code, counter} ->
        {:ok,
         """
         #{range_code}
           elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
           for (elmc_int_t #{item_var} = #{first_ref}; direct_rc == 0; #{item_var} += direct_step_#{next}) {
         #{Util.indent(body_code, 2)}
             if (#{item_var} == #{last_ref}) break;
           }
         """, counter}

      :error ->
        :error
    end
  end

  defp transparent_lambda_map_range_loop(_fun_expr, _range_code, _first_ref, _last_ref, _env, _counter),
    do: :error

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

    case Host.direct_emit_expr(body, body_env, next) do
      {:ok, body_code, counter} ->
        {:ok,
         """
         #{range_code}
           elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
           for (elmc_int_t #{item_var} = #{first_ref}, #{index_var} = 0; direct_rc == 0; #{item_var} += direct_step_#{next}, #{index_var} += 1) {
         #{Util.indent(body_code, 2)}
             if (#{item_var} == #{last_ref}) break;
           }
         """, counter}

      :error ->
        :error
    end
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
        end

      :error when transparent? ->
        case Host.direct_range_bounds(list_expr, env, counter) do
          {:ok, range_code, first_ref, last_ref, counter} ->
            transparent_lambda_map_range_loop(fun_expr, range_code, first_ref, last_ref, env, counter)

          :error ->
            :error
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
                  next,
                  env,
                  counter
                )
            end
        end
    end
  end

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
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; direct_rc == 0; direct_item_i_#{next} += direct_step_#{next}) {
         int direct_rc_#{next} = #{c_name}_commands_append_native(#{arg_list}, writer);
         if (direct_rc_#{next} < 0) {
     #{prefix_release_code}
           return direct_rc_#{next};
         }
         #{Catch.soft_stop_if("direct_rc_#{next}")}
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
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; direct_rc == 0; direct_item_i_#{next} += direct_step_#{next}) {
         ElmcValue *direct_index_value_#{next} = elmc_new_int(direct_index_#{next});
         ElmcValue *direct_item_value_#{next} = elmc_new_int(direct_item_i_#{next});
         ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
     #{prefix_bindings}
         direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
         direct_call_args_#{next}[#{prefix_count + 1}] = direct_item_value_#{next};
         int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, writer);
         elmc_release(direct_index_value_#{next});
         elmc_release(direct_item_value_#{next});
         if (direct_rc_#{next} < 0) {
     #{prefix_release_code}
           return direct_rc_#{next};
         }
         #{Catch.soft_stop_if("direct_rc_#{next}")}
         if (direct_item_i_#{next} == #{last_ref}) break;
         direct_index_#{next} += 1;
       }
     #{prefix_release_code}
     """, counter}
  end

  defp indexed_map_list_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         list_expr,
         c_name,
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)

    arg_list =
      Enum.join(
        prefix_refs ++
          ["direct_index_#{next}", "elmc_as_int(direct_node_#{next}->head)"],
        ", "
      )

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     ElmcValue *direct_cursor_#{next} = #{list_var};
        elmc_int_t direct_index_#{next} = 0;
     while (direct_rc == 0 && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
       ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
       int direct_rc_#{next} = #{c_name}_commands_append_native(#{arg_list}, writer);
       if (direct_rc_#{next} < 0) {
         elmc_release(#{list_var});
     #{prefix_release_code}
         return direct_rc_#{next};
       }
       #{Catch.soft_stop_if("direct_rc_#{next}")}
       direct_index_#{next} += 1;
       direct_cursor_#{next} = direct_node_#{next}->tail;
     }
     elmc_release(#{list_var});
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
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)
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

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     #{prefix_setup_code}
     ElmcValue *direct_cursor_#{next} = #{list_var};
        elmc_int_t direct_index_#{next} = 0;
     while (direct_rc == 0 && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
       ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
       ElmcValue *direct_index_value_#{next} = elmc_new_int(direct_index_#{next});
       ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
     #{prefix_arg_bindings}
       direct_call_args_#{next}[#{prefix_count}] = direct_index_value_#{next};
       direct_call_args_#{next}[#{prefix_count + 1}] = direct_node_#{next}->head;
       int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, writer);
       elmc_release(direct_index_value_#{next});
       if (direct_rc_#{next} < 0) {
         elmc_release(#{list_var});
     #{loop_prefix_release_code}
         return direct_rc_#{next};
       }
       #{Catch.soft_stop_if("direct_rc_#{next}")}
       direct_index_#{next} += 1;
       direct_cursor_#{next} = direct_node_#{next}->tail;
     }
     elmc_release(#{list_var});
     #{loop_prefix_release_code}
     """, counter}
  end


  defp compile_arg_values(args, env, counter) do
    Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
      {code, var, c2} = Host.compile_expr(arg_expr, env, c)
      {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
    end)
  end

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
          {code, ref, c2} = Host.compile_expr(arg_expr, env, c)
          {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ [ref], c2}
      end
    end)
  end

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

  defp indexed_map_arg_kinds(decl_map, {target_module, target_name, _prefix_args}) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{type: _} = decl -> CommandDef.arg_kinds(decl)
      _ -> []
    end
  end

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

  defp map_arg_kinds(decl_map, {target_module, target_name, _prefix_args}) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{type: _} = decl -> CommandDef.arg_kinds(decl)
      _ -> []
    end
  end

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
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; direct_rc == 0; direct_item_i_#{next} += direct_step_#{next}) {
         int direct_rc_#{next} = #{c_name}_commands_append_native(#{arg_list}, writer);
         if (direct_rc_#{next} < 0) {
     #{prefix_release_code}
           return direct_rc_#{next};
         }
         #{Catch.soft_stop_if("direct_rc_#{next}")}
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
      for (elmc_int_t direct_item_i_#{next} = #{first_ref}; direct_rc == 0; direct_item_i_#{next} += direct_step_#{next}) {
         ElmcValue *direct_item_value_#{next} = elmc_new_int(direct_item_i_#{next});
         ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
     #{prefix_bindings}
         direct_call_args_#{next}[#{prefix_count}] = direct_item_value_#{next};
         int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, writer);
         elmc_release(direct_item_value_#{next});
         if (direct_rc_#{next} < 0) {
     #{prefix_release_code}
           return direct_rc_#{next};
         }
         #{Catch.soft_stop_if("direct_rc_#{next}")}
         if (direct_item_i_#{next} == #{last_ref}) break;
       }
     #{prefix_release_code}
     """, counter}
  end

  defp map_list_loop(
         true,
         prefix_code,
         prefix_refs,
         prefix_release_code,
         list_expr,
         c_name,
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)

    arg_list =
      Enum.join(prefix_refs ++ ["elmc_as_int(direct_node_#{next}->head)"], ", ")

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     ElmcValue *direct_cursor_#{next} = #{list_var};
     while (direct_rc == 0 && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
       ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
       int direct_rc_#{next} = #{c_name}_commands_append_native(#{arg_list}, writer);
       if (direct_rc_#{next} < 0) {
         elmc_release(#{list_var});
     #{prefix_release_code}
         return direct_rc_#{next};
       }
       #{Catch.soft_stop_if("direct_rc_#{next}")}
       direct_cursor_#{next} = direct_node_#{next}->tail;
     }
     elmc_release(#{list_var});
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
         next,
         env,
         counter
       ) do
    {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)
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

    {:ok,
     """
     #{list_code}
     #{prefix_code}
     #{prefix_setup_code}
     ElmcValue *direct_cursor_#{next} = #{list_var};
     while (direct_rc == 0 && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
       ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
       ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
     #{prefix_arg_bindings}
       direct_call_args_#{next}[#{prefix_count}] = direct_node_#{next}->head;
       int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, writer);
       if (direct_rc_#{next} < 0) {
         elmc_release(#{list_var});
     #{loop_prefix_release_code}
         return direct_rc_#{next};
       }
       #{Catch.soft_stop_if("direct_rc_#{next}")}
       direct_cursor_#{next} = direct_node_#{next}->tail;
     }
     elmc_release(#{list_var});
     #{loop_prefix_release_code}
     """, counter}
  end

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
          int direct_rc_static_#{index} = #{c_name}_commands_append_native(#{arg_list}, writer);
          if (direct_rc_static_#{index} < 0) {
        #{prefix_release_code}
            return direct_rc_static_#{index};
          }
          #{Catch.soft_stop_if("direct_rc_static_#{index}")}
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
        {item_code, item_var, c2} = Host.compile_expr(item, env, c)

        snippet = """
        #{item_code}
          ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
        #{prefix_bindings}
          direct_call_args_#{next}[#{prefix_count}] = #{item_var};
          int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, writer);
          elmc_release(#{item_var});
          if (direct_rc_#{next} < 0) {
        #{prefix_release_code}
            return direct_rc_#{next};
          }
          #{Catch.soft_stop_if("direct_rc_#{next}")}
        """

        {acc <> snippet, c2}
      end)

    {:ok, prefix_code <> body <> prefix_release_code, counter}
  end

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
          int direct_rc_static_#{index} = #{c_name}_commands_append_native(#{arg_list}, writer);
          if (direct_rc_static_#{index} < 0) {
        #{prefix_release_code}
            return direct_rc_static_#{index};
          }
          #{Catch.soft_stop_if("direct_rc_static_#{index}")}
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
        {item_code, item_var, c2} = Host.compile_expr(item, env, c)
        index_var = "direct_static_index_#{c2}"
        next_c = c2 + 1

        snippet = """
        #{item_code}
          ElmcValue *#{index_var} = elmc_new_int(#{index});
          ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 2, 1)}] = {0};
        #{prefix_bindings}
          direct_call_args_#{next}[#{prefix_count}] = #{index_var};
          direct_call_args_#{next}[#{prefix_count + 1}] = #{item_var};
          int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 2}, writer);
          elmc_release(#{index_var});
          elmc_release(#{item_var});
          if (direct_rc_#{next} < 0) {
        #{prefix_release_code}
            return direct_rc_#{next};
          }
          #{Catch.soft_stop_if("direct_rc_#{next}")}
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

        with {:ok, body_code, counter} <- Host.direct_emit_expr(body, body_env, counter) do
          {:ok,
           """
           #{range_code}
            elmc_int_t direct_step_#{next} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
            for (elmc_int_t direct_item_i_#{next} = #{first_ref}; direct_rc == 0; direct_item_i_#{next} += direct_step_#{next}) {
           #{Util.indent(body_code, 4)}
               if (direct_item_i_#{next} == #{last_ref}) break;
             }
           """, counter}
        else
          _ -> :error
        end

      :error ->
        {list_code, list_var, counter} = Host.compile_expr(list_expr, env, counter)
        item_var = "direct_node_#{next}->head"
        body_env = Map.put(env, arg, item_var)

        with {:ok, body_code, counter} <- Host.direct_emit_expr(body, body_env, counter) do
          {:ok,
           """
           #{list_code}
             ElmcValue *direct_cursor_#{next} = #{list_var};
             while (direct_rc == 0 && direct_cursor_#{next} && direct_cursor_#{next}->tag == ELMC_TAG_LIST && direct_cursor_#{next}->payload != NULL) {
               ElmcCons *direct_node_#{next} = (ElmcCons *)direct_cursor_#{next}->payload;
           #{Util.indent(body_code, 4)}
               direct_cursor_#{next} = direct_node_#{next}->tail;
             }
             elmc_release(#{list_var});
           """, counter}
        else
          _ -> :error
        end
    end
  end

  defp boxed_prefix_call_args(prefix_vars, loop_id, counter) do
    Enum.reduce(prefix_vars, {"", [], "", counter}, fn var, {setup_acc, slots_acc, release_acc, c} ->
      if boxed_elmc_value_ref?(var) do
        {setup_acc, slots_acc ++ [var], release_acc, c}
      else
        next = c + 1
        boxed = "direct_prefix_boxed_#{loop_id}_#{next}"

        setup =
          setup_acc <>
            "  ElmcValue *#{boxed} = elmc_new_int(#{var});\n"

        release =
          release_acc <> Release.release_vars([boxed], "        ")

        {setup, slots_acc ++ [boxed], release, next}
      end
    end)
    |> then(fn {setup, slots, release, c} -> {setup, slots, release, c} end)
  end

  defp boxed_elmc_value_ref?(ref) when is_binary(ref) do
    Regex.match?(~r/^(tmp_\d+|model|elmc_|direct_node_|direct_cursor_|direct_item_|direct_index_)/, ref)
  end

  defp boxed_elmc_value_ref?(_), do: false
end
