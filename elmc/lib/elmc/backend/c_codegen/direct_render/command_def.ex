defmodule Elmc.Backend.CCodegen.DirectRender.CommandDef do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch
  alias Elmc.Backend.CCodegen.DirectRender.Emit.DuplicateFieldHoists
  alias Elmc.Backend.CCodegen.DirectRender.Emit.RecordGetHoistPass
  alias Elmc.Backend.CCodegen.DirectRender.PlanStreamEmit
  alias Elmc.Backend.Plan.StrictPolicy
  alias Elmc.Backend.CCodegen.DirectRender.RecordViewPeel
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.PebbleWatchPhaseScope
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
      ty = Enum.at(arg_types, index)

      cond do
        Host.color_type?(ty) -> :native_int
        Host.signature_param_kind(ty) == :native_int -> :native_int
        Host.signature_param_kind(ty) == :native_string -> :native_string
        true -> :boxed
      end
    end)
  end

  def arg_kinds(%{args: args}) when is_list(args), do: Enum.map(args, fn _ -> :boxed end)
  def arg_kinds(_decl), do: []

  @spec boxed_def(
          ElmEx.IR.Module.t(),
          Types.function_declaration(),
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
          __hoisted_native_ints_enabled__: true,
          __record_alias_shapes__: record_alias_shapes()
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

    borrow_refs =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> MapSet.new()

    Process.delete(:elmc_hoisted_native_ints)
    Process.delete(:elmc_hoisted_native_int_inits)
    Process.put(:elmc_hoisted_native_ints_scope, true)
    Process.put(:elmc_direct_borrow_refs, borrow_refs)
    Process.put(:elmc_direct_helper_defs, [])
    ValueSlots.reset(epilogue_lifo: true)
    Process.put(:elmc_direct_scene_boxed_argv, true)
    PebbleWatchPhaseScope.reset!()

    try do
      {field_hoist_preamble, start_counter} = DuplicateFieldHoists.preamble(decl.expr, env, 0)

      case emit_commands_body(decl, mod.name, decl_map, env, start_counter) do
        {:plan_stream, body_code} ->
          unused_casts = FunctionEmit.unused_arg_casts(c_arg_bindings, [body_code])
          helper_defs = direct_helper_defs()

          body_code =
            field_hoist_preamble <> body_code
            |> Hoist.drop_unused_native_minmax_decls()
            |> RecordGetHoistPass.run()

          helper_defs <>
            boxed_body(
              c_name,
              arg_bindings,
              unused_casts,
              body_code,
              mod,
              decl,
              skip_value_slots_owned: true
            )

        {:legacy, body_code, _counter} ->
          unused_casts =
            FunctionEmit.unused_arg_casts(c_arg_bindings, [body_code])

          helper_defs = direct_helper_defs()

          body_code =
            field_hoist_preamble <> body_code
            |> Hoist.drop_unused_native_minmax_decls()
            |> RecordGetHoistPass.run()

          helper_defs <> boxed_body(c_name, arg_bindings, unused_casts, body_code, mod, decl)

        :error ->
          raise ArgumentError, host_fallback_error(mod.name, decl.name)
      end
    after
      Process.delete(:elmc_direct_scene_boxed_argv)
      Process.delete(:elmc_direct_borrow_refs)
      Process.delete(:elmc_hoisted_native_ints_scope)
      Process.delete(:elmc_hoisted_native_ints)
      Process.delete(:elmc_hoisted_native_int_inits)
      Process.delete(:elmc_direct_helper_defs)
      PebbleWatchPhaseScope.reset!()
    end
  end

  @spec boxed_body(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          ElmEx.IR.Module.t(),
          Types.function_declaration()
        ) :: String.t()
  defp boxed_body(c_name, arg_bindings, unused_casts, body_code, mod, decl, catch_opts \\ []) do
    ValueSlots.ensure_covers_owned_refs(body_code)

    """
    static RC #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      #{arg_bindings}
      #{unused_casts}
      if (!writer)
        return RC_ERR_INVALID_ARG;
      #{Catch.function_body_prefix(catch_opts)}#{body_code}#{Catch.function_body_suffix(catch_opts)}
    }
    #{scene_append_stub(c_name, mod, decl)}
    """
  end

  @spec native_def(
          ElmEx.IR.Module.t(),
          Types.function_declaration(),
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
          __hoisted_native_ints_enabled__: true,
          __record_alias_shapes__: record_alias_shapes()
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

    borrow_refs =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> MapSet.new()

    Process.delete(:elmc_hoisted_native_ints)
    Process.delete(:elmc_hoisted_native_int_inits)
    Process.put(:elmc_hoisted_native_ints_scope, true)
    Process.put(:elmc_direct_borrow_refs, borrow_refs)
    Process.put(:elmc_direct_helper_defs, [])
    ValueSlots.reset(epilogue_lifo: true)
    Process.put(:elmc_direct_scene_boxed_argv, false)
    PebbleWatchPhaseScope.reset!()

    try do
      {field_hoist_preamble, start_counter} = DuplicateFieldHoists.preamble(decl.expr, native_env, 0)

      case emit_commands_body(decl, mod.name, decl_map, native_env, start_counter) do
        {:plan_stream, body_code} ->
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
              mod,
              decl,
              wrapper_unused_casts,
              native_unused_casts,
              field_hoist_preamble <> body_code
              |> Hoist.drop_unused_native_minmax_decls()
              |> RecordGetHoistPass.run(),
              skip_value_slots_owned: true
            )

        {:legacy, body_code, _counter} ->
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
              mod,
              decl,
              wrapper_unused_casts,
              native_unused_casts,
              field_hoist_preamble <> body_code
              |> Hoist.drop_unused_native_minmax_decls()
              |> RecordGetHoistPass.run()
            )

        :error ->
          raise ArgumentError, host_fallback_error(mod.name, decl.name)
      end
    after
      Process.delete(:elmc_direct_scene_boxed_argv)
      Process.delete(:elmc_direct_borrow_refs)
      Process.delete(:elmc_hoisted_native_ints_scope)
      Process.delete(:elmc_hoisted_native_ints)
      Process.delete(:elmc_hoisted_native_int_inits)
      Process.delete(:elmc_direct_helper_defs)
      PebbleWatchPhaseScope.reset!()
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
          ElmEx.IR.Module.t(),
          Types.function_declaration(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()
  defp native_body(
         c_name,
         wrapper_bindings,
         native_args,
         mod,
         decl,
         wrapper_unused_casts,
         native_unused_casts,
         body_code,
         catch_opts \\ []
       ) do
    ValueSlots.ensure_covers_owned_refs(body_code)

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
      #{Catch.function_body_prefix(catch_opts)}#{body_code}#{Catch.function_body_suffix(catch_opts)}
    }
    #{scene_append_stub(c_name, mod, decl)}
    """
  end

  @spec emit_commands_body(
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map(),
          Types.compile_env(),
          non_neg_integer()
        ) :: {:plan_stream, String.t()} | {:legacy, String.t(), non_neg_integer()} | :error
  defp emit_commands_body(decl, module_name, decl_map, env, start_counter) do
    case PlanStreamEmit.try_emit_body(decl, module_name, decl_map) do
      {:ok, body_code} ->
        {:plan_stream, body_code}

      :error ->
        case Host.direct_emit_expr(decl.expr, env, start_counter) do
          {:ok, body_code, counter} ->
            record_plan_stream_fallback(module_name, decl)

            if host_expr_dispatch_allowed?() do
              {:legacy, body_code, counter}
            else
              :error
            end

          :error ->
            :error
        end
    end
  end

  defp host_expr_dispatch_allowed? do
    opts = Process.get(:elmc_codegen_opts, %{})
    not StrictPolicy.strict?(opts)
  end

  defp host_fallback_error(module_name, name) do
    "direct Pebble command generation failed for #{module_name}.#{name} " <>
      "(Plan stream and ListLoop both failed; Host ExprDispatch is not a production fallback)"
  end

  defp record_plan_stream_fallback(module_name, decl) do
    cache = Process.get(:elmc_plan_unsupported_reasons, %{})
    op = Map.get(decl.expr || %{}, :op)
    target = Map.get(decl.expr || %{}, :target) || Map.get(decl.expr || %{}, :name)

    reason = %{
      source: "elmc/direct_render",
      code: "plan_stream_fallback",
      op: op,
      target: target
    }

    Process.put(
      :elmc_plan_unsupported_reasons,
      Map.put_new(cache, {module_name, decl.name}, reason)
    )

    opts = Process.get(:elmc_codegen_opts, %{})
    strict? = Map.get(opts, :plan_ir_strict, false)
    severity = if strict?, do: "error", else: "warning"

    warnings = Process.get(:elmc_compile_warnings, [])

    Process.put(:elmc_compile_warnings, [
      %{
        "severity" => severity,
        "source" => "elmc/direct_render",
        "code" => "plan_stream_fallback",
        "message" =>
          "Direct-render #{module_name}.#{decl.name} fell back to Host emit " <>
            "(Plan stream lower failed; op=#{inspect(op)} target=#{inspect(target)}). " <>
            if(strict?,
              do: "plan_ir_strict forbids ExprDispatch production fallback.",
              else: "Generated C must still typecheck."
            )
      }
      | warnings
    ])
  end

  defp scene_append_stub(c_name, mod, decl) do
    if entry_view_scene_append?(mod, decl) do
      """

      RC #{c_name}_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
        return #{c_name}_commands_append(args, argc, writer);
      }
      """
    else
      ""
    end
  end

  defp entry_view_scene_append?(mod, decl) do
    opts = Process.get(:elmc_codegen_opts, [])
    entry_module = opts[:entry_module] || "Main"
    mod.name == entry_module and decl.name == "view"
  end

  defp put_boxed_param_binding(env, module_name, decl, source_arg, c_arg, decl_map) do
    case RecordViewPeel.param_env_binding({module_name, decl.name}, source_arg, c_arg, decl_map) do
      nil -> Map.put(env, source_arg, c_arg)
      peel_binding -> Map.put(env, source_arg, peel_binding)
    end
  end

  defp record_alias_shapes do
    case Process.get(:elmc_record_alias_shapes) do
      shapes when is_map(shapes) -> shapes
      _ -> %{}
    end
  end
end
