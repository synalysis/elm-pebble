defmodule Elmc.Backend.CCodegen.DirectRender.Emit.CommandCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Release
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec emit_command_call(
          Types.function_decl_key(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()

  def emit_command_call(target_key, args, env, counter) do
    pruned = Map.get(env, :__direct_pruned__, MapSet.new())

    if MapSet.member?(pruned, target_key) do
      case emit_inline_command_call(target_key, args, env, counter) do
        {:ok, code, c} ->
          {:ok, code, c}

        :error ->
          {module_name, decl_name} = target_key

          raise ArgumentError,
                "direct Pebble command inline generation failed for #{module_name}.#{decl_name}"
      end
    else
      emit_outlined_command_call(target_key, args, env, counter)
    end
  end

  @spec emit_inline_command_call(
          Types.function_decl_key(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defp emit_inline_command_call(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})
    decl = Map.get(decl_map, target_key)

    with %{args: arg_names, expr: body_expr} when is_list(arg_names) <- decl,
         true <- length(arg_names) == length(args),
         {:ok, arg_code, inline_env, release_refs, counter} <-
           inline_command_env(target_key, args, arg_names, env, counter),
         {:ok, body_code, counter} <- Host.direct_emit_expr(body_expr, inline_env, counter) do
      releases = Release.release_vars(release_refs, "  ")

      {:ok,
       """
       if (!direct_stop) {
       #{arg_code}
       #{body_code}
       #{releases}
       }
       """, counter}
    else
      _ -> :error
    end
  end

  defp inline_command_env(target_key, args, arg_names, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})
    decl = Map.get(decl_map, target_key)
    arg_kinds = CommandDef.arg_kinds(decl)
    {module_name, _} = target_key

    {arg_code, inline_env, release_refs, counter} =
      args
      |> Enum.zip(arg_names)
      |> Enum.zip(arg_kinds)
      |> Enum.reduce(
        {"", env, [], counter},
        fn {{arg_expr, arg_name}, kind}, {code_acc, env_acc, releases_acc, c} ->
          case kind do
            :native_int ->
              {code, ref, c2} = Host.compile_native_int_expr(arg_expr, env, c)
              env_acc = EnvBindings.put_native_int_binding(env_acc, arg_name, ref)
              {code_acc <> "\n  " <> code, env_acc, releases_acc, c2}

            :native_string ->
              {code, ref, cleanup, c2} = Host.compile_native_string_expr(arg_expr, env, c)
              env_acc = EnvBindings.put_native_string_binding(env_acc, arg_name, ref)
              {code_acc <> "\n  " <> code, env_acc, releases_acc ++ cleanup, c2}

            :boxed ->
              {code, ref, c2} = Host.compile_expr(arg_expr, env, c)
              env_acc = Map.put(env_acc, arg_name, ref)
              {code_acc <> "\n  " <> code, env_acc, releases_acc ++ [ref], c2}
          end
        end
      )

    c_arg_bindings = Host.c_arg_bindings(arg_names)

    inline_env =
      inline_env
      |> Map.put(:__module__, module_name)
      |> Host.put_typed_arg_bindings(c_arg_bindings, decl.type)

    {:ok, arg_code, inline_env, release_refs, counter}
  end

  defp emit_outlined_command_call(target_key, args, env, counter) do
    decl_map = Map.get(env, :__program_decls__, %{})
    decl = Map.get(decl_map, target_key)

    arg_kinds =
      if decl, do: CommandDef.arg_kinds(decl), else: Enum.map(args, fn _ -> :boxed end)

    {arg_code, arg_refs, release_refs, counter} =
      args
      |> Enum.zip(arg_kinds)
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

    next = counter + 1
    c_name = Util.module_fn_name(elem(target_key, 0), elem(target_key, 1))
    argc = length(arg_refs)
    arg_list = Enum.join(arg_refs, ", ")
    releases = Release.release_vars(release_refs, "  ")

    if Enum.any?(arg_kinds, &(&1 != :boxed)) do
      {:ok,
       """
       if (!direct_stop) {
       #{arg_code}
         int direct_rc_#{next} = #{c_name}_commands_append_native(#{arg_list}, out_cmds, max_cmds, skip, count, emitted);
       #{releases}
         if (direct_rc_#{next} < 0) return direct_rc_#{next};
         if (*count >= max_cmds) direct_stop = 1;
       }
       """, next}
    else
      {:ok,
       """
       if (!direct_stop) {
       #{arg_code}
         ElmcValue *direct_call_args_#{next}[#{max(argc, 1)}] = { #{arg_list} };
         int direct_rc_#{next} = #{c_name}_commands_append(direct_call_args_#{next}, #{argc}, out_cmds, max_cmds, skip, count, emitted);
       #{releases}
         if (direct_rc_#{next} < 0) return direct_rc_#{next};
         if (*count >= max_cmds) direct_stop = 1;
       }
       """, next}
    end
  end
end
