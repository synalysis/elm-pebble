defmodule Elmc.Backend.CCodegen.FunctionEmit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LetAnalysis
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.ListIntReduce
  alias Elmc.Backend.CCodegen.Native.ListIntSearch
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.ImmortalStaticList
  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @c_reserved_binding_names ~w(args argc out_cmds max_cmds skip count emitted)

  @spec emit_function_def(
          Types.function_declaration(),
          String.t(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          boolean()
        ) :: String.t()
  def emit_function_def(
        decl,
        module_name,
        c_name,
        function_arities,
        decl_map,
        emit_wrapper?
      ) do
    if NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) do
      emit_native_function_def(
        decl,
        module_name,
        c_name,
        function_arities,
        decl_map,
        emit_wrapper?
      )
    else
      Process.put(:elmc_generic_helper_defs, [])
      Process.put(:elmc_generic_helper_counter, 0)
      direct_args? = not emit_wrapper?
      {immortal_prelude, body} = emit_body(decl, module_name, function_arities, decl_map, direct_args?)
      helper_defs = generic_helper_defs()
      Process.delete(:elmc_generic_helper_defs)
      Process.delete(:elmc_generic_helper_counter)

      policy =
        if direct_args? do
          "#{Enum.join(decl.ownership, ", ")}, direct_call_abi"
        else
          Enum.join(decl.ownership, ", ")
        end

      rc_required? = RcRequired.rc_required?(module_name, decl.name)

      signature =
        cond do
          rc_required? -> rc_function_params(direct_args?, decl)
          direct_args? -> boxed_direct_params(decl)
          true -> "ElmcValue ** const args, const int argc"
        end

      return_type = if rc_required?, do: "RC", else: "ElmcValue *"

      linkage = function_linkage_prefix(module_name, decl.name)

      """
      #{immortal_prelude}#{if immortal_prelude == "", do: "", else: "\n"}
      #{helper_defs}#{linkage}#{return_type} #{c_name}(#{signature}) {
        /* Ownership policy: #{policy} */
      #{body}
      }
      """
      |> String.trim_trailing()
    end
  end

  @spec function_linkage_prefix(String.t(), String.t()) :: String.t()
  defp function_linkage_prefix(module_name, decl_name) do
    exported? =
      Process.get(:elmc_exported_targets, MapSet.new())
      |> MapSet.member?({module_name, decl_name})

    if exported?, do: "", else: "static "
  end

  @spec rc_function_params(boolean(), Types.function_declaration()) :: String.t()
  defp rc_function_params(direct_args?, decl) do
    params =
      if direct_args? do
        boxed_direct_params(decl)
      else
        "ElmcValue ** const args, const int argc"
      end

    case params do
      "void" -> "ElmcValue **out"
      other -> "ElmcValue **out, #{other}"
    end
  end

  @spec boxed_direct_params(Types.function_declaration()) :: String.t()
  def boxed_direct_params(decl) do
    case c_arg_bindings(decl.args || []) do
      [] ->
        "void"

      bindings ->
        bindings
        |> Enum.map(fn {_arg, c_arg, _index} -> "ElmcValue *#{c_arg}" end)
        |> Enum.join(", ")
    end
  end

  @spec boxed_direct_prototype(Types.function_declaration(), String.t(), String.t(), String.t()) ::
          String.t()
  def boxed_direct_prototype(decl, c_name, module_name, decl_name) do
    params = boxed_direct_params(decl)

    if RcRequired.rc_required?(module_name, decl_name) do
      case params do
        "void" -> "RC #{c_name}(ElmcValue **out);"
        other -> "RC #{c_name}(ElmcValue **out, #{other});"
      end
    else
      case params do
        "void" -> "ElmcValue *#{c_name}(void);"
        other -> "ElmcValue *#{c_name}(#{other});"
      end
    end
  end

  @spec boxed_function_prototype(
          Types.function_declaration(),
          String.t(),
          String.t(),
          boolean(),
          Types.function_decl_map()
        ) :: String.t()
  def boxed_function_prototype(decl, module_name, c_name, emit_wrapper?, decl_map) do
    cond do
      RcRequired.rc_required?(module_name, decl.name) ->
        if emit_wrapper? or NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) do
          "RC #{c_name}(ElmcValue **out, ElmcValue ** const args, const int argc);"
        else
          boxed_direct_prototype(decl, c_name, module_name, decl.name)
        end

      emit_wrapper? or NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) ->
        "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"

      true ->
        boxed_direct_prototype(decl, c_name, module_name, decl.name)
    end
  end

  defp generic_helper_defs do
    :elmc_generic_helper_defs
    |> Process.get([])
    |> Enum.reverse()
    |> Enum.join("\n")
    |> case do
      "" -> ""
      defs -> defs <> "\n"
    end
  end

  @spec emit_body(
          Types.function_declaration(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          boolean()
        ) :: {String.t(), String.t()}
  def emit_body(
        decl,
        module_name,
        function_arities \\ %{},
        decl_map \\ %{},
        direct_args? \\ false
      )

  def emit_body(%{expr: nil}, _module_name, _function_arities, _decl_map, _direct_args?) do
    {"", "(void)args; (void)argc; return elmc_int_zero();"}
  end

  def emit_body(decl, module_name, function_arities, decl_map, direct_args?) do
    rc_required? = RcRequired.rc_required?(module_name, decl.name)

    with true <- ImmortalStaticList.zero_arg_function?(decl),
         {:ok, prelude, body} <-
           ImmortalStaticList.try_emit_function_prelude_and_body(
             module_name,
             decl.name,
             decl.expr || %{op: :int_literal, value: 0},
             direct_args?,
             rc_required?
           ) do
      {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

      body =
        format_function_body([
          entry_probe,
          body,
          exit_probe
        ])

      {prelude, body}
    else
      _ ->
        {"", emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?)}
    end
  end

  defp emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?) do
    rc_required? = RcRequired.rc_required?(module_name, decl.name)
    if rc_required?, do: ValueSlots.reset()

    arg_names = decl.args || []
    arg_bindings = c_arg_bindings(arg_names)
    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)
    arg_binding_code = arg_binding_code(arg_bindings, direct_args?)

    env =
      arg_bindings
      |> Enum.reduce(%{__module__: module_name}, fn arg, acc ->
        {source_arg, c_arg, _index} = arg
        Map.put(acc, source_arg, c_arg)
      end)
      |> Map.put(:__function_name__, decl.name)
      |> put_typed_arg_bindings(arg_bindings, decl.type)
      |> Map.put(:__function_arities__, function_arities)
      |> Map.put(:__program_decls__, decl_map)
      |> maybe_put_direct_args(direct_args?)
      |> maybe_put_direct_param_refs(direct_args?, arg_bindings)
      |> EnvBindings.put_borrowed_arg_refs(decl, arg_bindings)
      |> Map.put(:__direct_call_targets__, Process.get(:elmc_direct_call_targets, MapSet.new()))
      |> Map.put(:__rc_required__, rc_required?)
      |> Map.put(:__rc_catch__, false)
      |> Map.put(
        :__function_analysis__,
        LetAnalysis.analyze_function_expr(
          decl.expr || %{op: :int_literal, value: 0},
          module_name,
          decl_map
        )
      )

    case boxed_special_body_emit(
           module_name,
           decl,
           decl_map,
           arg_bindings,
           direct_args?,
           entry_probe,
           exit_probe,
         arg_binding_code,
         rc_required?
       ) do
      {:ok, body} ->
        body

      :error ->
        compile_env =
          if rc_required?, do: Map.put(env, :__rc_catch__, true), else: env

        {code, result_var, _counter} =
          Host.compile_expr(decl.expr || %{op: :int_literal, value: 0}, compile_env, 0)

        if rc_required?, do: ValueSlots.track(result_var)

        result_probe = DebugProbes.result_probe(module_name, decl.name, result_var)

        core_body =
          [
            entry_probe,
            code,
            exit_probe,
            result_probe,
            if(rc_required?, do: "*out = #{result_var};", else: "return #{result_var};")
          ]

        if rc_required? do
          wrap_rc_function_body(
            arg_bindings,
            arg_binding_code,
            core_body,
            direct_args?
          )
        else
          unused_casts = unused_arg_casts(arg_bindings, core_body)

          format_function_body(
            [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts |
               core_body]
          )
        end
    end
  end

  defp wrap_rc_function_body(
         arg_bindings,
         arg_binding_code,
         core_body,
         direct_args?
       ) do
    body_text = Enum.join(List.wrap(core_body), "\n")
    owned_decls = ValueSlots.owned_declarations_for_body(body_text)
    failure_cleanup = ValueSlots.failure_cleanup_for_body(body_text)
    unused_casts = unused_arg_casts(arg_bindings, core_body)
    needs_catch? = rc_body_needs_catch?(body_text)

    prefix =
      ["RC Rc = RC_SUCCESS;"] ++
        List.wrap(owned_decls) ++
        [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts]

    suffix =
      if(failure_cleanup == "",
        do: [],
        else: ["if (Rc != RC_SUCCESS) {", failure_cleanup, "}"]
      ) ++
        ["return Rc;"]

    core =
      if needs_catch? do
        ["", "CATCH_BEGIN"] ++ core_body ++ ["CATCH_END;", ""]
      else
        ["" | core_body] ++ [""]
      end

    format_rc_function_body(prefix ++ core ++ suffix)
  end

  defp rc_body_needs_catch?(body_text) when is_binary(body_text) do
    String.contains?(body_text, "CHECK_RC") or
      String.contains?(body_text, "CHECK_RC_TO") or
      String.contains?(body_text, "\nbreak;")
  end

  defp format_rc_function_body(parts) do
    parts
    |> List.flatten()
    |> Enum.join("\n")
    |> CSource.format_block(2)
  end

  defp maybe_put_direct_args(env, true), do: Map.put(env, :__direct_args__, true)
  defp maybe_put_direct_args(env, _), do: env

  defp maybe_put_direct_param_refs(env, true, arg_bindings),
    do: EnvBindings.put_direct_param_refs(env, arg_bindings)

  defp maybe_put_direct_param_refs(env, _, _arg_bindings), do: env

  defp arg_binding_code(arg_bindings, direct_args?) do
    if direct_args? do
      ""
    else
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, index} ->
        "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)
      |> Enum.join("\n")
    end
  end

  defp wrapper_abi_void_casts(true, _arg_bindings), do: ""

  defp wrapper_abi_void_casts(false, arg_bindings) when arg_bindings == [] do
    "(void)args;\n(void)argc;"
  end

  defp wrapper_abi_void_casts(false, _arg_bindings), do: ""

  defp format_function_body(parts) do
    parts
    |> List.flatten()
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join("\n")
    |> CSource.format_block(2)
  end

  defp boxed_special_body_emit(
         module_name,
         decl,
         decl_map,
         arg_bindings,
         direct_args?,
         entry_probe,
         exit_probe,
         arg_binding_code,
         rc_required?
       ) do
    tuple2_table? =
      match?({:ok, _, _}, Tuple2CaseTable.try_emit(module_name, decl.name, decl.expr))

    case Fusion.try_emit(module_name, decl.name, decl.expr, decl_map) do
      {:ok, _helper_c, _, :rc_native} when tuple2_table? ->
        {:error}

      {:ok, helper_c, _, :rc_native} ->
        {:ok,
         emit_rc_fused_native_wrapper_function(
           decl,
           module_name,
           arg_bindings,
           direct_args?,
           helper_c,
           entry_probe,
           exit_probe,
           arg_binding_code
         )}

      {:ok, helper_c, _} when tuple2_table? ->
        {:ok,
         emit_tuple2_table_function(
           decl,
           module_name,
           arg_bindings,
           direct_args?,
           helper_c,
           entry_probe,
           exit_probe,
           arg_binding_code,
           rc_required?
         )}

      {:ok, helper_c, _} ->
        {:ok,
         emit_fused_native_wrapper_function(
           decl,
           module_name,
           decl_map,
           arg_bindings,
           direct_args?,
           helper_c,
           entry_probe,
           exit_probe,
           arg_binding_code,
           rc_required?
         )}

      :error ->
        :error
    end
  end

  defp emit_fused_native_wrapper_function(
         decl,
         module_name,
         _decl_map,
         arg_bindings,
         direct_args?,
         helper_c,
         entry_probe,
         exit_probe,
         arg_binding_code,
         rc_required?
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    Process.put(
      :elmc_generic_helper_defs,
      [helper_c | Process.get(:elmc_generic_helper_defs, [])]
    )

    native_args = fused_native_call_args(decl, arg_bindings)
    if rc_required?, do: ValueSlots.track("tmp_result")

    core_body = [
      entry_probe,
      "ElmcValue *tmp_result = #{native}(#{native_args});",
      exit_probe,
      if(rc_required?, do: "*out = tmp_result;", else: "return tmp_result;")
    ]

    if rc_required? do
      wrap_rc_function_body(
        arg_bindings,
        arg_binding_code,
        core_body,
        direct_args?
      )
    else
      unused_casts = unused_arg_casts(arg_bindings, core_body)

      format_function_body(
        [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts |
           core_body]
      )
    end
  end

  defp emit_rc_fused_native_wrapper_function(
         decl,
         module_name,
         arg_bindings,
         direct_args?,
         helper_c,
         entry_probe,
         exit_probe,
         arg_binding_code
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    Process.put(
      :elmc_generic_helper_defs,
      [helper_c | Process.get(:elmc_generic_helper_defs, [])]
    )

    native_args =
      if direct_args? do
        (["out"] ++ Enum.map(arg_bindings, fn {_arg, c_arg, _index} -> c_arg end))
        |> Enum.join(", ")
      else
        native_call_args =
          case decl do
            %{type: type} when is_binary(type) ->
              arg_types = Host.function_arg_types(type)

              arg_bindings
              |> Enum.zip(arg_types)
              |> Enum.map(fn {{_arg, c_arg, _index}, arg_type} ->
                case Host.normalize_type_name(arg_type) do
                  "Int" -> "elmc_as_int(#{c_arg})"
                  "Bool" -> "elmc_as_bool(#{c_arg})"
                  _other -> c_arg
                end
              end)

            _ ->
              Enum.map(arg_bindings, fn {_arg, c_arg, _index} -> c_arg end)
          end

        (["out" | native_call_args])
        |> Enum.join(", ")
      end

    core_body = [
      entry_probe,
      "return #{native}(#{native_args});",
      exit_probe
    ]

    unused_casts = unused_arg_casts(arg_bindings, core_body)

    format_function_body(
      [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts | core_body]
    )
  end

  defp fused_native_call_args(%{type: type}, arg_bindings) when is_binary(type) do
    arg_types = Host.function_arg_types(type)

    arg_bindings
    |> Enum.zip(arg_types)
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, arg_type} ->
      case Host.normalize_type_name(arg_type) do
        "Int" -> "elmc_as_int(#{c_arg})"
        "Bool" -> "elmc_as_bool(#{c_arg})"
        _other -> c_arg
      end
    end)
  end

  defp fused_native_call_args(_decl, arg_bindings) do
    arg_bindings
    |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
    |> Enum.join(", ")
  end

  defp emit_tuple2_table_function(
         decl,
         module_name,
         arg_bindings,
         direct_args?,
         helper_c,
         entry_probe,
         exit_probe,
         arg_binding_code,
         rc_required?
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    Process.put(
      :elmc_generic_helper_defs,
      [helper_c | Process.get(:elmc_generic_helper_defs, [])]
    )

    native_args =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> "elmc_as_int(#{c_arg})" end)
      |> Enum.join(", ")

    if rc_required?, do: ValueSlots.track("tmp_result")

    core_body = [
      entry_probe,
      "ElmcValue *tmp_result = #{native}(#{native_args});",
      exit_probe,
      if(rc_required?, do: "*out = tmp_result;", else: "return tmp_result;")
    ]

    if rc_required? do
      wrap_rc_function_body(
        arg_bindings,
        arg_binding_code,
        core_body,
        direct_args?
      )
    else
      unused_casts = unused_arg_casts(arg_bindings, core_body)

      format_function_body(
        [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts |
           core_body]
      )
    end
  end

  @spec generic_native_function_prototypes(
          ElmEx.IR.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: String.t()
  def generic_native_function_prototypes(ir, generic_targets, decl_map) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(
        &(&1.kind == :function and MapSet.member?(generic_targets, {mod.name, &1.name}) and
            NativeFunctionCall.native_scalar_fn?(&1, mod.name, decl_map))
      )
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        return_kind = NativeFunctionCall.return_kind(decl, mod.name, decl_map)

        "static #{native_return_prefix(return_kind)}#{c_name}_native(#{NativeFunctionCall.params(decl, mod.name, decl_map)});"
      end)
    end)
    |> Enum.join("\n")
  end

  @spec generic_function_prototypes(
          ElmEx.IR.t(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          MapSet.t(Types.function_decl_key())
        ) :: String.t()
  def generic_function_prototypes(
        ir,
        generic_targets,
        wrapper_targets,
        decl_map,
        exported_targets
      ) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(fn decl ->
        target = {mod.name, decl.name}

        decl.kind == :function and MapSet.member?(generic_targets, target) and
          (MapSet.member?(wrapper_targets, target) or
             not NativeFunctionCall.native_scalar_fn?(decl, mod.name, decl_map))
      end)
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        emit_wrapper? = MapSet.member?(wrapper_targets, {mod.name, decl.name})

        prefix =
          if MapSet.member?(exported_targets, {mod.name, decl.name}), do: "", else: "static "

        prefix <> boxed_function_prototype(decl, mod.name, c_name, emit_wrapper?, decl_map)
      end)
    end)
    |> Enum.join("\n")
  end

  @spec c_arg_bindings([String.t()]) :: [Types.c_arg_binding()]
  def c_arg_bindings(arg_names) do
    arg_names
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      c_arg =
        cond do
          arg == "_" -> "_unused_#{index}"
          c_reserved_binding_name?(arg) -> "#{arg}_arg"
          Enum.count(arg_names, &(&1 == arg)) > 1 -> "#{arg}_#{index}"
          true -> arg
        end

      {arg, c_arg, index}
    end)
  end

  @spec put_typed_arg_bindings(Types.compile_env(), [Types.c_arg_binding()], String.t() | nil) ::
          Types.compile_env()
  def put_typed_arg_bindings(env, arg_bindings, type) when is_binary(type) do
    arg_types = TypeParsing.function_arg_types(type)

    arg_bindings
    |> Enum.zip(arg_types)
    |> Enum.reduce(env, fn {{arg, _c_arg, _index}, arg_type}, acc ->
      normalized_type = TypeParsing.normalize_type_name(arg_type)

      acc =
        case normalized_type do
          "Int" ->
            EnvBindings.put_boxed_int_binding(acc, arg, true)

          "Bool" ->
            EnvBindings.put_boxed_bool_binding(acc, arg, true)

          _other ->
            if TypeParsing.enum_type?(arg_type),
              do: EnvBindings.put_boxed_int_binding(acc, arg, true),
              else: acc
        end

      acc
      |> EnvBindings.put_record_shape(arg, Expr.record_shape_from_type(normalized_type, acc))
      |> put_var_type(arg, normalized_type)
    end)
  end

  def put_typed_arg_bindings(env, _arg_bindings, _type), do: env

  @spec c_reserved_binding_name?(String.t()) :: boolean()
  defp c_reserved_binding_name?(name), do: name in @c_reserved_binding_names

  defp put_var_type(env, name, type), do: EnvBindings.put_var_type(env, name, type)

  @spec emit_native_function_def(
          Types.function_declaration(),
          String.t(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          boolean()
        ) :: String.t()
  defp emit_native_function_def(
         decl,
         module_name,
         c_name,
         function_arities,
         decl_map,
         emit_wrapper?
       ) do
    arg_names = decl.args || []
    c_arg_bindings = c_arg_bindings(arg_names)
    arg_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)
    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

    wrapper_bindings =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.map_join("\n  ", fn {{_arg, c_arg, index}, kind} ->
        case kind do
          :native_int ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"

          :native_bool ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_bool(args[#{index}]) : 0;"

          :boxed ->
            "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    return_kind = NativeFunctionCall.return_kind(decl, module_name, decl_map)
    native_env = native_env(decl, module_name, function_arities, decl_map, return_kind)

    collect_generic_helpers? = return_kind == :boxed

    if collect_generic_helpers? do
      Process.put(:elmc_generic_helper_defs, [])
      Process.put(:elmc_generic_helper_counter, 0)
    end

    {helper_defs, native_def} =
      case return_kind do
        :boxed ->
          case native_boxed_special_emit(module_name, decl, decl_map) do
            {:ok, helper_c, _callees, :rc_native} ->
              {helper_c <> "\n", ""}

            {:ok, helper_c, _callees} ->
              {helper_c <> "\n", ""}

            :error ->
              compile_native_function_body(
                decl,
                module_name,
                c_name,
                decl_map,
                native_env,
                return_kind,
                arg_kinds,
                c_arg_bindings,
                entry_probe,
                exit_probe,
                collect_generic_helpers?
              )
          end

        _ ->
          compile_native_function_body(
            decl,
            module_name,
            c_name,
            decl_map,
            native_env,
            return_kind,
            arg_kinds,
            c_arg_bindings,
            entry_probe,
            exit_probe,
            false
          )
      end

    wrapper_def =
      if emit_wrapper? do
        linkage = function_linkage_prefix(module_name, decl.name)
        rc_required? = RcRequired.rc_required?(module_name, decl.name)

        signature =
          if rc_required? do
            "RC #{c_name}(ElmcValue **out, ElmcValue ** const args, const int argc)"
          else
            "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc)"
          end

        return_stmt =
          cond do
            rc_required? and return_kind == :boxed ->
              """
              ElmcValue *tmp_result = #{c_name}_native(#{native_args});
              *out = tmp_result;
              return RC_SUCCESS;
              """

            rc_required? and return_kind == :native_int ->
              """
              *out = elmc_new_int_take(#{c_name}_native(#{native_args}));
              return RC_SUCCESS;
              """

            rc_required? and return_kind == :native_bool ->
              """
              *out = elmc_new_bool_take(#{c_name}_native(#{native_args}));
              return RC_SUCCESS;
              """

            true ->
              wrapper_return(c_name, native_args, return_kind)
          end

        wrapper_unused_casts =
          unused_arg_casts(c_arg_bindings, [wrapper_bindings, return_stmt])

        """
        #{linkage}#{signature} {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          #{wrapper_bindings}
          #{wrapper_unused_casts}
          #{return_stmt}
        }
        """
      else
        ""
      end

    """
    #{wrapper_def}
    #{helper_defs}#{native_def}
    """
  end

  defp native_boxed_special_emit(module_name, decl, decl_map) do
    case Fusion.try_emit(module_name, decl.name, decl.expr, decl_map) do
      {:ok, helper_c, callees, :rc_native} -> {:ok, helper_c, callees, :rc_native}
      {:ok, helper_c, callees} -> {:ok, helper_c, callees}
      :error -> :error
    end
  end

  defp compile_native_function_body(
         decl,
         module_name,
         c_name,
         decl_map,
         native_env,
         return_kind,
         arg_kinds,
         c_arg_bindings,
         entry_probe,
         exit_probe,
         collect_generic_helpers?
       ) do
    {body_code, body_var, _counter} =
      compile_native_body(decl, module_name, decl_map, native_env, return_kind, arg_kinds)

    unused_casts =
      unused_arg_casts(c_arg_bindings, [body_code, entry_probe, exit_probe, "return #{body_var};"])

    case_helpers =
      if collect_generic_helpers? do
        generic_helper_defs_and_clear()
      else
        ""
      end

    native_def = """
    static #{native_return_prefix(return_kind)}#{c_name}_native(#{NativeFunctionCall.params(decl, module_name, decl_map)}) {
      #{unused_casts}
      #{entry_probe}
      #{body_code}
      #{exit_probe}
      return #{body_var};
    }
    """

    {case_helpers, native_def}
  end

  defp generic_helper_defs_and_clear do
    defs = generic_helper_defs()
    Process.delete(:elmc_generic_helper_defs)
    Process.delete(:elmc_generic_helper_counter)
    defs
  end

  @spec native_env(
          Types.function_declaration(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          NativeFunctionCall.native_return_kind()
        ) :: Types.compile_env()
  defp native_env(decl, module_name, function_arities, decl_map, return_kind) do
    c_arg_bindings = c_arg_bindings(decl.args || [])
    arg_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)

    c_arg_bindings
    |> Enum.zip(arg_kinds)
    |> Enum.reduce(%{__module__: module_name}, fn {{source_arg, c_arg, _index}, kind}, acc ->
      case kind do
        :native_int -> EnvBindings.put_native_int_binding(acc, source_arg, c_arg)
        :native_bool -> EnvBindings.put_native_bool_binding(acc, source_arg, c_arg)
        :boxed -> Map.put(acc, source_arg, c_arg)
      end
    end)
    |> put_typed_arg_bindings(c_arg_bindings, decl.type)
    |> Map.put(:__function_name__, decl.name)
    |> Map.put(:__function_arities__, function_arities)
    |> Map.put(:__program_decls__, decl_map)
    |> EnvBindings.put_borrowed_arg_refs(decl, c_arg_bindings)
    |> Map.put(:__direct_call_targets__, Process.get(:elmc_direct_call_targets, MapSet.new()))
    |> Map.put(
      :__function_analysis__,
      LetAnalysis.analyze_function_expr(
        decl.expr || %{op: :int_literal, value: 0},
        module_name,
        decl_map
      )
    )
    |> Map.put(:__native_return_kind__, return_kind)
  end

  defp compile_native_body(decl, module_name, decl_map, env, return_kind, arg_kinds)
       when return_kind in [:native_int, :native_bool] do
    expr = decl.expr || %{op: :int_literal, value: 0}

    case compile_list_int_search_native(decl, module_name, decl_map, env, return_kind) do
      {:ok, code, result_var} ->
        {code, result_var, 0}

      :error ->
        case compile_list_int_reduce_native(decl, module_name, decl_map, env, return_kind) do
          {:ok, code, result_var} ->
            {code, result_var, 0}

          :error ->
            case compile_tail_recursive_native(decl, module_name, env, return_kind, arg_kinds) do
              {:ok, code, result_var} ->
                {code, result_var, 0}

              :error ->
                compile_scalar_native_expr(expr, env, return_kind, 0)
            end
        end
    end
  end

  defp compile_native_body(decl, _module_name, _decl_map, env, :boxed, _arg_kinds) do
    env = RecordCompile.with_subexpr_cache(env)
    Host.compile_expr(decl.expr || %{op: :int_literal, value: 0}, env, 0)
  end

  defp compile_list_int_search_native(decl, module_name, decl_map, env, return_kind) do
    with {:ok, spec} <- ListIntSearch.recognize(decl, module_name, decl_map),
         {:ok, code, result_var} <-
           ListIntSearch.compile(spec, env, return_kind, &compile_scalar_native_expr/4) do
      {:ok, code, result_var}
    else
      :error ->
        with {:ok, spec} <- ListIntSearch.recognize_delegate(decl, module_name, decl_map),
             {:ok, code, result_var} <- ListIntSearch.compile_delegate(spec, env) do
          {:ok, code, result_var}
        else
          _ -> :error
        end
    end
  end

  defp compile_list_int_reduce_native(decl, module_name, decl_map, env, return_kind) do
    with {:ok, spec} <- ListIntReduce.recognize(decl, module_name, decl_map),
         {:ok, code, result_var} <-
           ListIntReduce.compile(spec, env, return_kind, &compile_scalar_native_expr/4) do
      {:ok, code, result_var}
    else
      _ -> :error
    end
  end

  defp compile_scalar_native_expr(expr, env, :native_int, counter),
    do: NativeInt.compile_expr(expr, env, counter)

  defp compile_scalar_native_expr(expr, env, :native_bool, counter),
    do: NativeBool.compile_expr(expr, env, counter)

  defp compile_tail_recursive_native(decl, module_name, env, return_kind, arg_kinds) do
    arg_names = decl.args || []

    with true <- arg_names != [],
         true <- Enum.all?(arg_kinds, &(&1 in [:native_int, :native_bool])),
         {:if_tail, cond_expr, base_expr, recursive_args, recurse_on_truthy?} <-
           tail_recursive_if(decl.expr, decl.name),
         true <- length(recursive_args) == length(arg_names) do
      c_arg_bindings = c_arg_bindings(arg_names)

      loop_bindings =
        c_arg_bindings
        |> Enum.zip(arg_kinds)
        |> Enum.map_join("\n  ", fn {{_arg, c_arg, _index}, kind} ->
          "elmc_int_t #{loop_arg_name(c_arg)} = #{c_arg}; /* #{kind} */"
        end)

      loop_env =
        c_arg_bindings
        |> Enum.zip(arg_kinds)
        |> Enum.reduce(env, fn {{source_arg, c_arg, _index}, kind}, acc ->
          case kind do
            :native_int ->
              EnvBindings.put_native_int_binding(acc, source_arg, loop_arg_name(c_arg))

            :native_bool ->
              EnvBindings.put_native_bool_binding(acc, source_arg, loop_arg_name(c_arg))
          end
        end)

      {cond_code, cond_ref, _} = NativeBool.compile_expr(cond_expr, loop_env, 0)
      {base_code, base_ref, _} = compile_scalar_native_expr(base_expr, loop_env, return_kind, 0)

      updates =
        recursive_args
        |> Enum.zip(c_arg_bindings)
        |> Enum.zip(arg_kinds)
        |> Enum.reduce({"", []}, fn {{arg_expr, {_source_arg, c_arg, _index}}, kind},
                                    {code_acc, refs_acc} ->
          {arg_code, arg_ref, _} =
            compile_scalar_native_expr(arg_expr, loop_env, kind, length(refs_acc))

          next_ref = "#{loop_arg_name(c_arg)}_next"
          code = code_acc <> "\n" <> arg_code <> "\n      elmc_int_t #{next_ref} = #{arg_ref};"
          {code, refs_acc ++ [{loop_arg_name(c_arg), next_ref}]}
        end)

      {update_code, update_refs} = updates

      assignments =
        update_refs
        |> Enum.map_join("\n      ", fn {target, next_ref} -> "#{target} = #{next_ref};" end)

      result_var = "tail_result"
      continue_branch = tail_continue_branch(update_code, assignments)
      base_branch = tail_base_branch(base_code, result_var, base_ref)

      {then_branch, else_branch} =
        if recurse_on_truthy?,
          do: {continue_branch, base_branch},
          else: {base_branch, continue_branch}

      code = """
      #{loop_bindings}
        elmc_int_t #{result_var} = 0;
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

  defp tail_recursive_if(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}, name) do
    cond do
      self_call?(then_expr, name) ->
        {:if_tail, cond, else_expr, then_expr.args || [], true}

      self_call?(else_expr, name) ->
        {:if_tail, cond, then_expr, else_expr.args || [], false}

      true ->
        :error
    end
  end

  defp tail_recursive_if(_expr, _name), do: :error

  defp self_call?(%{op: :call, name: name}, name), do: true
  defp self_call?(_expr, _name), do: false

  defp loop_arg_name(c_arg), do: "#{c_arg}_loop"

  defp tail_continue_branch(update_code, assignments) do
    """
    #{update_code}
      #{assignments}
      continue;
    """
  end

  defp tail_base_branch(base_code, result_var, base_ref) do
    """
    #{base_code}
      #{result_var} = #{base_ref};
      break;
    """
  end

  defp wrapper_return(c_name, native_args, :native_int),
    do: "return elmc_new_int_take(#{c_name}_native(#{native_args}));"

  defp wrapper_return(c_name, native_args, :native_bool),
    do: "return elmc_new_bool_take(#{c_name}_native(#{native_args}));"

  defp wrapper_return(c_name, native_args, :boxed), do: "return #{c_name}_native(#{native_args});"

  defp native_return_prefix(:boxed), do: "ElmcValue *"
  defp native_return_prefix(return_kind), do: "#{NativeFunctionCall.c_return_type(return_kind)} "

  @doc false
  @spec unused_arg_casts([{term(), String.t(), non_neg_integer()}], iolist()) :: String.t()
  def unused_arg_casts(arg_bindings, body_parts) do
    body_text = body_parts |> List.flatten() |> Enum.join("\n")

    arg_bindings
    |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
    |> Enum.reject(&arg_referenced?(&1, body_text))
    |> case do
      [] -> ""
      names -> Enum.map_join(names, "\n", &"(void)#{&1};")
    end
  end

  defp arg_referenced?(c_arg, body_text) do
    Regex.match?(~r/(?:\W|^)#{Regex.escape(c_arg)}(?:\W|$)/, body_text)
  end
end
