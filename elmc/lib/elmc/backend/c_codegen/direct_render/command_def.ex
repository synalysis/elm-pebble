defmodule Elmc.Backend.CCodegen.DirectRender.CommandDef do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch
  alias Elmc.Backend.CCodegen.DirectRender.Emit.DuplicateFieldHoists
  alias Elmc.Backend.CCodegen.DirectRender.RecordViewPeel
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @type arg_kind :: Types.direct_command_arg_kind()
  @type c_arg_binding :: Types.c_arg_binding()

  @spec def(
          ElmEx.IR.Module.t(),
          Types.function_declaration(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: String.t()
  def def(mod, decl, targets, pruned, decl_map) do
    c_name = Util.module_fn_name(mod.name, decl.name)
    arg_names = decl.args || []
    c_arg_bindings = Host.c_arg_bindings(arg_names)
    arg_kinds = arg_kinds(decl)

    if Enum.any?(arg_kinds, &(&1 != :boxed)) do
      native_def(mod, decl, targets, pruned, decl_map, c_name, c_arg_bindings, arg_kinds)
    else
      boxed_def(mod, decl, targets, pruned, decl_map, c_name, c_arg_bindings)
    end
  end

  @spec native_args?(Types.function_declaration()) :: boolean()
  def native_args?(decl) do
    decl
    |> arg_kinds()
    |> Enum.any?(&(&1 != :boxed))
  end

  @spec native_params(Types.function_declaration()) :: String.t()
  def native_params(decl) do
    Host.c_arg_bindings(decl.args || [])
    |> Enum.zip(arg_kinds(decl))
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> "const elmc_int_t #{c_arg}"
        :native_string -> "const char * const #{c_arg}"
        :boxed -> "ElmcValue * const #{c_arg}"
      end
    end)
  end

  @spec arg_kinds(Types.function_declaration()) :: [arg_kind()]
  def arg_kinds(%{args: args, type: type}) when is_list(args) and is_binary(type) do
    arg_types = Host.function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {_arg, index} ->
      case Enum.at(arg_types, index) |> Host.normalize_type_name() do
        "Int" -> :native_int
        "Pebble.Ui.Color.Color" -> :native_int
        "String" -> :native_string
        _other -> :boxed
      end
    end)
  end

  def arg_kinds(%{args: args}) when is_list(args), do: Enum.map(args, fn _ -> :boxed end)
  def arg_kinds(_decl), do: []

  @spec boxed_def(
          map(),
          map(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          String.t(),
          [c_arg_binding()]
        ) :: String.t()
  defp boxed_def(mod, decl, targets, pruned, decl_map, c_name, c_arg_bindings) do
    arg_bindings =
      c_arg_bindings
      |> Enum.map_join("\n  ", fn {_arg, c_arg, index} ->
        "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)

    env =
      c_arg_bindings
      |> Enum.reduce(
        %{
          __module__: mod.name,
          __direct_targets__: targets,
          __program_decls__: decl_map,
          __direct_pruned__: pruned,
          __hoisted_native_ints_enabled__: true
        },
        fn arg, acc ->
          {source_arg, c_arg, _index} = arg
          put_boxed_param_binding(acc, mod.name, decl, source_arg, c_arg, decl_map)
        end
      )
      |> Host.put_typed_arg_bindings(c_arg_bindings, decl.type)
      |> EnvBindings.put_direct_param_refs(c_arg_bindings)
      |> Map.put(:__rc_catch__, true)
      |> Map.put(:__rc_required__, true)

    Process.delete(:elmc_hoisted_native_ints)
    Process.delete(:elmc_hoisted_native_int_inits)
    Process.put(:elmc_hoisted_native_ints_scope, true)
    Process.put(:elmc_direct_helper_defs, [])
    ValueSlots.reset(epilogue_lifo: true)

    try do
      {field_hoist_preamble, start_counter} = DuplicateFieldHoists.preamble(decl.expr, env, 0)

      case Host.direct_emit_expr(decl.expr, env, start_counter) do
        {:ok, body_code, _counter} ->
          unused_casts =
            FunctionEmit.unused_arg_casts(c_arg_bindings, [body_code])

          helper_defs = direct_helper_defs()
          helper_defs <> boxed_body(c_name, arg_bindings, unused_casts, Hoist.drop_unused_native_minmax_decls(field_hoist_preamble <> body_code))

        :error ->
          raise ArgumentError,
                "direct Pebble command generation failed for #{mod.name}.#{decl.name}"
      end
    after
      Process.delete(:elmc_hoisted_native_ints_scope)
      Process.delete(:elmc_hoisted_native_ints)
      Process.delete(:elmc_hoisted_native_int_inits)
      Process.delete(:elmc_direct_helper_defs)
    end
  end

  @spec boxed_body(String.t(), String.t(), String.t(), String.t()) :: String.t()
  defp boxed_body(c_name, arg_bindings, unused_casts, body_code) do
    """
    static RC #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      #{arg_bindings}
      #{unused_casts}
      if (!writer)
        return RC_ERR_INVALID_ARG;
      #{Catch.function_body_prefix()}#{body_code}#{Catch.function_body_suffix()}
    }

    RC #{c_name}_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      return #{c_name}_commands_append(args, argc, writer);
    }
    """
  end

  @spec native_def(
          map(),
          map(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          String.t(),
          [c_arg_binding()],
          [arg_kind()]
        ) :: String.t()
  defp native_def(mod, decl, targets, pruned, decl_map, c_name, c_arg_bindings, arg_kinds) do
    wrapper_bindings =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.map_join("\n  ", fn {{_arg, c_arg, index}, kind} ->
        case kind do
          :native_int ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"

          :native_string ->
            """
            const char *#{c_arg} =
              (argc > #{index} && args[#{index}] && args[#{index}]->tag == ELMC_TAG_STRING && args[#{index}]->payload)
                ? (const char *)args[#{index}]->payload
                : "";
            """

          :boxed ->
            "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    native_env =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.reduce(
        %{
          __module__: mod.name,
          __direct_targets__: targets,
          __program_decls__: decl_map,
          __direct_pruned__: pruned,
          __hoisted_native_ints_enabled__: true
        },
        fn {{source_arg, c_arg, _index}, kind}, acc ->
          case kind do
            :native_int -> EnvBindings.put_native_int_binding(acc, source_arg, c_arg)
            :native_string -> EnvBindings.put_native_string_binding(acc, source_arg, c_arg)
            :boxed -> put_boxed_param_binding(acc, mod.name, decl, source_arg, c_arg, decl_map)
          end
        end
      )
      |> Host.put_typed_arg_bindings(c_arg_bindings, decl.type)
      |> EnvBindings.put_direct_param_refs(c_arg_bindings)
      |> Map.put(:__rc_catch__, true)
      |> Map.put(:__rc_required__, true)

    Process.delete(:elmc_hoisted_native_ints)
    Process.delete(:elmc_hoisted_native_int_inits)
    Process.put(:elmc_hoisted_native_ints_scope, true)
    Process.put(:elmc_direct_helper_defs, [])
    ValueSlots.reset(epilogue_lifo: true)

    try do
      {field_hoist_preamble, start_counter} = DuplicateFieldHoists.preamble(decl.expr, native_env, 0)

      case Host.direct_emit_expr(decl.expr, native_env, start_counter) do
        {:ok, body_code, _counter} ->
          wrapper_unused_casts =
            FunctionEmit.unused_arg_casts(c_arg_bindings, [wrapper_bindings, native_args])

          native_unused_casts =
            FunctionEmit.unused_arg_casts(c_arg_bindings, [body_code])

          helper_defs = direct_helper_defs()

          helper_defs <>
            native_body(
              c_name,
              wrapper_bindings,
              native_args,
              decl,
              wrapper_unused_casts,
              native_unused_casts,
              field_hoist_preamble <> body_code
              |> Hoist.drop_unused_native_minmax_decls()
            )

        :error ->
          raise ArgumentError,
                "direct Pebble command generation failed for #{mod.name}.#{decl.name}"
      end
    after
      Process.delete(:elmc_hoisted_native_ints_scope)
      Process.delete(:elmc_hoisted_native_ints)
      Process.delete(:elmc_hoisted_native_int_inits)
      Process.delete(:elmc_direct_helper_defs)
    end
  end

  defp direct_helper_defs do
    :elmc_direct_helper_defs
    |> Process.get([])
    |> Enum.reverse()
    |> Enum.join("\n")
    |> case do
      "" -> ""
      defs -> defs <> "\n"
    end
  end

  @spec native_body(
          String.t(),
          String.t(),
          String.t(),
          map(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()
  defp native_body(
         c_name,
         wrapper_bindings,
         native_args,
         decl,
         wrapper_unused_casts,
         native_unused_casts,
         body_code
       ) do
    """
    static RC #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      #{wrapper_bindings}
      #{wrapper_unused_casts}
      return #{c_name}_commands_append_native(#{native_args}, writer);
    }

    static RC #{c_name}_commands_append_native(#{native_params(decl)}, ElmcSceneWriter * const writer) {
      #{native_unused_casts}
      if (!writer)
        return RC_ERR_INVALID_ARG;
      #{Catch.function_body_prefix()}#{body_code}#{Catch.function_body_suffix()}
    }

    RC #{c_name}_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      return #{c_name}_commands_append(args, argc, writer);
    }
    """
  end

  defp put_boxed_param_binding(env, module_name, decl, source_arg, c_arg, decl_map) do
    case RecordViewPeel.param_env_binding({module_name, decl.name}, source_arg, c_arg, decl_map) do
      nil -> Map.put(env, source_arg, c_arg)
      peel_binding -> Map.put(env, source_arg, peel_binding)
    end
  end
end
