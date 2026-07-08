defmodule Elmc.Backend.CCodegen.FunctionEmit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.ConstantInt
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
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.FunctionCallAbi
  alias Elmc.Backend.CCodegen.FunctionSplit
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.PlanNativeProjection
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.ImmortalStaticList
  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.PrimaryCoverage

  @c_reserved_binding_names ~w(
    args argc out_cmds max_cmds skip count emitted
    auto break case char const continue default do double else enum extern float for goto
    if inline int long register restrict return short signed sizeof static struct switch
    typedef union unsigned void volatile while _Bool _Complex _Imaginary
  )

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
    cond do
      plan_primary_function?(decl, module_name, decl_map) ->
        emit_boxed_function_def(
          decl,
          module_name,
          c_name,
          function_arities,
          decl_map,
          emit_wrapper?
        )

      NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) ->
        emit_native_function_def(
          decl,
          module_name,
          c_name,
          function_arities,
          decl_map,
          emit_wrapper?
        )

      true ->
        emit_boxed_function_def(
          decl,
          module_name,
          c_name,
          function_arities,
          decl_map,
          emit_wrapper?
        )
    end
  end

  defp emit_boxed_function_def(
         decl,
         module_name,
         c_name,
         function_arities,
         decl_map,
         emit_wrapper?
       ) do
    Process.put(:elmc_generic_helper_defs, [])
    Process.put(:elmc_generic_helper_counter, 0)
    direct_args? =
      FunctionCallAbi.direct_entry_abi?(decl, module_name, decl_map) or
        not worker_rc_abi?(emit_wrapper?, module_name, decl.name, decl_map)
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
        rc_required? -> rc_function_params(direct_args?, decl, module_name, decl_map)
        direct_args? -> direct_params(decl, module_name, decl_map)
        true -> "ElmcValue ** const args, const int argc"
      end

    return_type = if rc_required?, do: "RC", else: "ElmcValue *"

    linkage = function_linkage_prefix(module_name, decl.name)

    native_projection =
      if plan_primary_body?(decl, module_name, decl_map, Process.get(:elmc_codegen_opts, [])) and
           PlanNativeProjection.eligible?(decl, module_name, decl_map) do
        PlanNativeProjection.emit(decl, module_name, decl_map)
      else
        ""
      end

    """
    #{immortal_prelude}#{if immortal_prelude == "", do: "", else: "\n"}
    #{helper_defs}#{linkage}#{return_type} #{c_name}(#{signature}) {
      /* Ownership policy: #{policy} */
    #{body}
    }
    #{native_projection}
    """
    |> String.trim_trailing()
  end

  defp plan_primary_function?(decl, module_name, decl_map) do
    Plan.primary_lowered?(decl, module_name, decl_map)
  end

  defp skip_native_def?(decl, module_name, decl_map) do
    skippable_zero_arg_native?(decl, module_name, decl_map)
  end

  defp emit_native_prototype?(decl, module_name, decl_map) do
    emit_native_function?(decl, module_name, decl_map) or
      not skippable_zero_arg_native?(decl, module_name, decl_map)
  end

  defp skippable_zero_arg_native?(decl, module_name, decl_map) do
    (decl.args || []) == [] and
      not NativeFunctionCall.native_args?(decl, module_name, decl_map) and
      not ListIntSearch.recognized?(decl, module_name, decl_map) and
      not match?({:ok, _}, ListIntReduce.recognize(decl, module_name, decl_map)) and
      NativeFunctionCall.return_kind(decl, module_name, decl_map) in [:native_int, :native_bool] and
      native_zero_arg_literal_body?(decl, module_name, decl_map)
  end

  defp native_zero_arg_literal_body?(decl, module_name, decl_map) do
    case decl do
      %{expr: %{op: op, value: _}} when op in [:int_literal, :char_literal, :bool_literal, :c_int_expr] ->
        true

      %{expr: expr} when is_map(expr) ->
        env =
          %{}
          |> Map.put(:__module__, module_name)
          |> Map.put(:__program_decls__, decl_map)

        case Elmc.Backend.CCodegen.ConstantInt.literal_value(expr, env) do
          {:ok, _} -> true
          :error -> false
        end

      _ ->
        false
    end
  end

  defp emit_native_function?(decl, module_name, decl_map) do
    not skip_native_def?(decl, module_name, decl_map)
  end

  @spec function_linkage_prefix(String.t(), String.t()) :: String.t()
  defp function_linkage_prefix(module_name, decl_name) do
    exported? =
      Process.get(:elmc_exported_targets, MapSet.new())
      |> MapSet.member?({module_name, decl_name})

    if exported?, do: "", else: "static "
  end

  @spec rc_function_params(
          boolean(),
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map()
        ) :: String.t()
  defp rc_function_params(direct_args?, decl, module_name, decl_map) do
    params =
      if direct_args? do
        direct_params(decl, module_name, decl_map)
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

  @spec mixed_direct_abi?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def mixed_direct_abi?(decl, module_name, decl_map) do
    decl
    |> NativeFunctionCall.arg_kinds(module_name, decl_map)
    |> Enum.any?(&(&1 in [:native_int, :native_bool]))
  end

  @spec direct_params(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          String.t()
  def direct_params(decl, module_name, decl_map) do
    case c_arg_bindings(decl.args || []) do
      [] ->
        "void"

      bindings ->
        kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)

        bindings
        |> Enum.zip(kinds)
        |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
          case kind do
            :native_int -> "elmc_int_t #{c_arg}"
            :native_bool -> "bool #{c_arg}"
            :boxed -> "ElmcValue *#{c_arg}"
          end
        end)
    end
  end

  @spec boxed_direct_prototype(
          Types.function_declaration(),
          String.t(),
          String.t(),
          String.t(),
          Types.function_decl_map()
        ) :: String.t()
  def boxed_direct_prototype(decl, c_name, module_name, decl_name, decl_map) do
    params = direct_params(decl, module_name, decl_map)

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
    worker_abi? = worker_rc_abi?(emit_wrapper?, module_name, decl.name, decl_map)

    cond do
      FunctionCallAbi.direct_entry_abi?(decl, module_name, decl_map) ->
        boxed_direct_prototype(decl, c_name, module_name, decl.name, decl_map)

      worker_abi? and not NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) ->
        if RcRequired.rc_required?(module_name, decl.name) do
          "RC #{c_name}(ElmcValue **out, ElmcValue ** const args, const int argc);"
        else
          "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"
        end

      RcRequired.rc_required?(module_name, decl.name) ->
        if worker_abi? or NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) do
          "RC #{c_name}(ElmcValue **out, ElmcValue ** const args, const int argc);"
        else
          boxed_direct_prototype(decl, c_name, module_name, decl.name, decl_map)
        end

      worker_abi? or NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) ->
        "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"

      true ->
        boxed_direct_prototype(decl, c_name, module_name, decl.name, decl_map)
    end
  end

  defp worker_rc_abi?(emit_wrapper?, module_name, decl_name, decl_map) do
    emit_wrapper? or RcRequired.platform_worker_rc_abi?(module_name, decl_name, decl_map)
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

  def emit_body(%{expr: nil} = decl, module_name, _function_arities, _decl_map, _direct_args?) do
    stub =
      if RcRequired.rc_required?(module_name, decl.name) do
        "(void)args; (void)argc; *out = elmc_int_zero(); return RC_SUCCESS;"
      else
        "(void)args; (void)argc; return elmc_int_zero();"
      end

    {"", stub}
  end

  def emit_body(decl, module_name, function_arities, decl_map, direct_args?) do
    rc_required? = RcRequired.rc_required?(module_name, decl.name)
    opts = Process.get(:elmc_codegen_opts, [])

    if plan_primary_body?(decl, module_name, decl_map, opts) do
      {"", emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?)}
    else
      emit_body_immortal_or_boxed(
        decl,
        module_name,
        function_arities,
        decl_map,
        direct_args?,
        rc_required?
      )
    end
  end

  defp emit_body_immortal_or_boxed(
         decl,
         module_name,
         function_arities,
         decl_map,
         direct_args?,
         rc_required?
       ) do
    with true <- ImmortalStaticList.zero_arg_function?(decl),
         {:ok, prelude, body} <-
           ImmortalStaticList.try_emit_function_prelude_and_body(
             module_name,
             decl.name,
             decl.expr || %{op: :int_literal, value: 0},
             direct_args?,
             rc_required?
           ) do
      RecordCompile.reset_borrowed_field_refs()
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

  defp plan_primary_body?(decl, module_name, decl_map, opts) do
    Plan.plan_ir_mode(opts) == :primary and Plan.primary_lowered?(decl, module_name, decl_map)
  end

  defp emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?) do
    rc_required? = RcRequired.rc_required?(module_name, decl.name)
    opts = Process.get(:elmc_codegen_opts, [])

    if rc_required? and not plan_primary_body?(decl, module_name, decl_map, opts) do
      ValueSlots.reset(epilogue_lifo: true)
    end

    RecordCompile.reset_borrowed_field_refs()

    arg_names = decl.args || []
    arg_bindings = c_arg_bindings(arg_names)
    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)
    arg_binding_code = arg_binding_code(arg_bindings, direct_args?)

    arg_kinds =
      if direct_args? and mixed_direct_abi?(decl, module_name, decl_map) do
        NativeFunctionCall.arg_kinds(decl, module_name, decl_map)
      else
        List.duplicate(:boxed, length(arg_names))
      end

    env =
      arg_bindings
      |> Enum.reduce(%{__module__: module_name}, fn arg, acc ->
        {source_arg, c_arg, _index} = arg
        Map.put(acc, source_arg, c_arg)
      end)
      |> Map.put(:__function_name__, decl.name)
      |> put_typed_arg_bindings(arg_bindings, decl.type)
      |> put_direct_native_param_bindings(arg_bindings, arg_kinds)
      |> Map.put(:__function_arities__, function_arities)
      |> Map.put(:__program_decls__, decl_map)
      |> maybe_put_direct_args(direct_args?)
      |> maybe_put_direct_param_refs(direct_args?, arg_bindings)
      |> EnvBindings.put_borrowed_arg_refs(decl, arg_bindings)
      |> Map.put(:__direct_call_targets__, Process.get(:elmc_direct_call_targets, MapSet.new()))
      |> Map.put(:__rc_required__, rc_required?)
      |> Map.put(:__rc_catch__, false)
      |> Map.put(:__record_field_types__, Process.get(:elmc_record_field_types, %{}))
      |> Map.put(
        :__function_analysis__,
        LetAnalysis.analyze_function_expr(
          decl.expr || %{op: :int_literal, value: 0},
          module_name,
          decl_map
        )
      )

    opts = Process.get(:elmc_codegen_opts, [])

    if Plan.plan_ir_mode(opts) == :primary do
      case maybe_emit_primary_plan_body(
             decl,
             module_name,
             decl_map,
             arg_bindings,
             arg_binding_code,
             direct_args?,
             rc_required?,
             entry_probe,
             exit_probe
           ) do
        {:ok, body} ->
          body

        :legacy ->
          opts = Process.get(:elmc_codegen_opts, [])

          if Plan.strict_primary?(opts) and
               primary_fallback_reachable?(module_name, decl.name, opts) do
            raise ArgumentError,
                  "plan_ir_strict: cannot lower reachable function #{module_name}.#{decl.name} to Plan IR"
          else
            emit_primary_legacy_fallback(
              decl,
              module_name,
              env,
              arg_bindings,
              arg_binding_code,
              direct_args?,
              rc_required?,
              entry_probe,
              exit_probe,
              arg_kinds
            )
          end
      end
    else
      emit_boxed_body_fusion_or_legacy(
        module_name,
        decl,
        decl_map,
        env,
        arg_bindings,
        direct_args?,
        entry_probe,
        exit_probe,
        arg_binding_code,
        rc_required?,
        arg_kinds,
        opts
      )
    end
  end

  defp emit_primary_legacy_fallback(
         decl,
         module_name,
         env,
         arg_bindings,
         arg_binding_code,
         direct_args?,
         rc_required?,
         entry_probe,
         exit_probe,
         arg_kinds
       ) do
    record_plan_primary_fallback(module_name, decl.name)

    emit_legacy_boxed_body(
      decl,
      module_name,
      env,
      arg_bindings,
      arg_binding_code,
      direct_args?,
      rc_required?,
      entry_probe,
      exit_probe,
      arg_kinds
    )
  end

  defp record_plan_primary_fallback(module_name, fun_name)
       when is_binary(module_name) and is_binary(fun_name) do
    key = :elmc_plan_primary_fallbacks

    fallbacks =
      Process.get(key, [])
      |> then(fn acc ->
        if {module_name, fun_name} in acc, do: acc, else: [{module_name, fun_name} | acc]
      end)

    Process.put(key, fallbacks)
    :ok
  end

  defp primary_fallback_reachable?(module_name, fun_name, opts) do
    decl_map = Process.get(:elmc_program_decls, %{})
    PrimaryCoverage.reachable_function?(decl_map, module_name, fun_name, opts)
  end

  defp emit_boxed_body_fusion_or_legacy(
         module_name,
         decl,
         decl_map,
         env,
         arg_bindings,
         direct_args?,
         entry_probe,
         exit_probe,
         arg_binding_code,
         rc_required?,
         arg_kinds,
         opts
       ) do
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
        _ =
          if Plan.plan_ir_mode(opts) == :shadow do
            Plan.shadow_verify(decl, module_name, decl_map,
              Keyword.merge(compile_opts_list(opts),
                rc_required: rc_required?,
                plan_ir_raise: plan_ir_raise?(opts)
              )
            )
          else
            :skipped
          end

        case maybe_emit_primary_plan_body(
               decl,
               module_name,
               decl_map,
               arg_bindings,
               arg_binding_code,
               direct_args?,
               rc_required?,
               entry_probe,
               exit_probe
             ) do
          {:ok, body} ->
            body

          :legacy ->
            emit_legacy_boxed_body(
              decl,
              module_name,
              env,
              arg_bindings,
              arg_binding_code,
              direct_args?,
              rc_required?,
              entry_probe,
              exit_probe,
              arg_kinds
            )
        end
    end
  end

  defp emit_legacy_boxed_body(
         decl,
         module_name,
         env,
         arg_bindings,
         arg_binding_code,
         direct_args?,
         rc_required?,
         entry_probe,
         exit_probe,
         arg_kinds
       ) do
    compile_env =
      if rc_required?,
        do:
          env
          |> Map.put(:__rc_catch__, true)
          |> Map.put(:__function_rc_out_param__, RcRuntimeEmit.function_out_param()),
        else: env

    root_env =
      if rc_required?, do: RcRuntimeEmit.function_tail_env(compile_env), else: compile_env

    FunctionCallCompile.reset_call_args_cache!()
    ValueSlots.reset_closure_call_arg_consumed!()

    {code, result_var, _counter} =
      case compile_tail_recursive(
             decl,
             module_name,
             compile_env,
             arg_bindings,
             arg_kinds,
             :boxed
           ) do
        {:ok, loop_code, tail_result} ->
          {loop_code, tail_result, 0}

        :error ->
          Host.compile_expr(decl.expr || %{op: :int_literal, value: 0}, root_env, 0)
      end

    unless rc_required? and RcRuntimeEmit.function_out_ref?(result_var),
      do: ValueSlots.track(result_var)

    result_probe = DebugProbes.result_probe(module_name, decl.name, result_var)

    core_body =
      [
        entry_probe,
        code,
        exit_probe,
        result_probe,
        if(rc_required? and not RcRuntimeEmit.function_out_ref?(result_var),
          do: publish_rc_function_out(result_var),
          else: if(not rc_required?, do: "return #{result_var};", else: nil)
        )
      ]
      |> Enum.reject(&is_nil/1)

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

  defp maybe_emit_primary_plan_body(
         decl,
         module_name,
         decl_map,
         arg_bindings,
         arg_binding_code,
         direct_args?,
         rc_required?,
         entry_probe,
         exit_probe
       ) do
    opts = Process.get(:elmc_codegen_opts, [])

    if Plan.plan_ir_mode(opts) != :primary do
      :legacy
    else
      case Plan.lower_function(decl, module_name, decl_map, rc_required: rc_required?) do
        {:ok, plan} ->
          result_probe = DebugProbes.result_probe(module_name, decl.name, "*out")

          plan_core =
            plan
            |> CLowerFunction.emit()
            |> insert_plan_result_probe(result_probe)

          body =
            format_function_body(
              [
                wrapper_abi_void_casts(direct_args?, arg_bindings),
                arg_binding_code,
                entry_probe,
                plan_core,
                exit_probe
              ]
              |> Enum.reject(&(&1 == ""))
            )

          {:ok, body}

        _ ->
          :legacy
      end
    end
  end

  defp compile_opts_list(opts) when is_list(opts), do: opts
  defp compile_opts_list(opts) when is_map(opts), do: Map.to_list(opts)
  defp compile_opts_list(_), do: []

  defp plan_ir_raise?(opts) when is_list(opts), do: Keyword.get(opts, :plan_ir_raise, false)
  defp plan_ir_raise?(opts) when is_map(opts), do: Map.get(opts, :plan_ir_raise, false)
  defp plan_ir_raise?(_), do: false

  defp insert_plan_result_probe(body, ""), do: body

  defp insert_plan_result_probe(body, probe) when is_binary(probe) and is_binary(body) do
    case String.split(body, "\n  return Rc;", parts: 2) do
      [prefix, suffix] ->
        indented = probe |> String.trim() |> String.replace("\n", "\n  ")
        prefix <> "\n  " <> indented <> "\n  return Rc;" <> suffix

      _ ->
        body
    end
  end

  defp wrap_rc_function_body(
         arg_bindings,
         arg_binding_code,
         core_body,
         direct_args?
       ) do
    body_text = Enum.join(List.wrap(core_body), "\n")
    owned_decls = ValueSlots.owned_declaration()
    failure_cleanup = ValueSlots.failure_cleanup()
    unused_casts = unused_arg_casts(arg_bindings, core_body)
    needs_catch? = rc_body_needs_catch?(body_text)

    prefix =
      ["RC Rc = RC_SUCCESS;"] ++
        List.wrap(owned_decls) ++
        [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts]

    suffix =
      epilogue_suffix(failure_cleanup, body_text, needs_catch?) ++
        ["return Rc;"]

    core =
      if needs_catch? do
        ["", "CATCH_BEGIN"] ++ [body_text] ++ ["CATCH_END;", ""]
      else
        ["" , body_text, ""]
      end

    format_rc_function_body(prefix ++ core ++ suffix)
  end

  defp rc_body_needs_catch?(body_text) when is_binary(body_text) do
    String.contains?(body_text, "CHECK_RC") or
      String.contains?(body_text, "CHECK_RC_TO") or
      String.contains?(body_text, "\nbreak;")
  end

  defp epilogue_suffix(failure_cleanup, _body_text, _needs_catch?) do
    if failure_cleanup == "", do: [], else: [failure_cleanup]
  end

  defp publish_rc_function_out(result_var) do
    RcRuntimeEmit.publish_function_out_from(result_var)
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

  defp put_direct_native_param_bindings(env, arg_bindings, arg_kinds) do
    arg_bindings
    |> Enum.zip(arg_kinds)
    |> Enum.reduce(env, fn {{source_arg, c_arg, _index}, kind}, acc ->
      case kind do
        :native_int ->
          acc
          |> EnvBindings.put_native_int_binding(source_arg, c_arg)
          |> EnvBindings.put_boxed_int_binding(source_arg, false)

        :native_bool ->
          acc
          |> EnvBindings.put_native_bool_binding(source_arg, c_arg)
          |> EnvBindings.put_boxed_bool_binding(source_arg, false)

        :boxed ->
          acc
      end
    end)
  end

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
    if plan_primary_body?(decl, module_name, decl_map, Process.get(:elmc_codegen_opts, [])) do
      :error
    else
      boxed_special_body_emit_fusion(
        module_name,
        decl,
        decl_map,
        arg_bindings,
        direct_args?,
        entry_probe,
        exit_probe,
        arg_binding_code,
        rc_required?
      )
    end
  end

  defp boxed_special_body_emit_fusion(
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
    tuple2_table? = Tuple2CaseTable.recognized?(module_name, decl.name, decl.expr)

    case Fusion.try_emit(module_name, decl.name, decl.expr, decl_map) do
      {:ok, helper_c, _, :rc_native} when tuple2_table? ->
        {:ok,
         emit_rc_tuple2_table_function(
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
           arg_binding_code,
           rc_required?
         )}

      {:ok, helper_c, _} when tuple2_table? ->
        {:ok,
         emit_tuple2_table_function(
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

    native_args = fused_native_call_args(decl, arg_bindings, direct_args?)

    core_body = [
      entry_probe,
      if(rc_required?,
        do: "*out = #{native}(#{native_args});",
        else: "return #{native}(#{native_args});"
      ),
      exit_probe
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
         arg_binding_code,
         rc_required?
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    Process.put(
      :elmc_generic_helper_defs,
      [helper_c | Process.get(:elmc_generic_helper_defs, [])]
    )

    fused_args =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    core_body =
      cond do
        rc_required? ->
          native_args =
            if direct_args? do
              ["out", fused_args] |> Enum.join(", ")
            else
              ["out", fused_args] |> Enum.join(", ")
            end

          [
            entry_probe,
            "return #{native}(#{native_args});",
            exit_probe
          ]

        true ->
          [
            entry_probe,
            "ElmcValue *tmp_result = NULL;",
            "if (#{native}(&tmp_result, #{fused_args}) != RC_SUCCESS) return NULL;",
            exit_probe,
            "return tmp_result;"
          ]
      end

    unused_casts = unused_arg_casts(arg_bindings, core_body)

    format_function_body(
      [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts |
         core_body]
    )
  end

  defp fused_native_call_args(%{type: type}, arg_bindings, direct_args?) when is_binary(type) do
    arg_types = Host.function_arg_types(type)

    arg_bindings
    |> Enum.zip(arg_types)
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, arg_type} ->
      kind =
        case Host.normalize_type_name(arg_type) do
          "Int" -> :native_int
          "Bool" -> :native_bool
          _ -> :boxed
        end

      native_scalar_call_arg(c_arg, kind, direct_args?)
    end)
  end

  defp fused_native_call_args(_decl, arg_bindings, _direct_args?) do
    arg_bindings
    |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
    |> Enum.join(", ")
  end

  defp tuple2_table_native_args(decl, module_name, decl_map, arg_bindings, direct_args?) do
    kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)

    arg_bindings
    |> Enum.zip(kinds)
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      native_scalar_call_arg(c_arg, kind, direct_args?)
    end)
  end

  defp native_scalar_call_arg(c_arg, :native_int, true), do: c_arg
  defp native_scalar_call_arg(c_arg, :native_bool, true), do: c_arg
  defp native_scalar_call_arg(c_arg, :native_int, false), do: "elmc_as_int(#{c_arg})"
  defp native_scalar_call_arg(c_arg, :native_bool, false), do: "elmc_as_bool(#{c_arg})"
  defp native_scalar_call_arg(c_arg, _kind, _direct_args?), do: c_arg

  defp emit_rc_tuple2_table_function(
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
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    Process.put(
      :elmc_generic_helper_defs,
      [helper_c | Process.get(:elmc_generic_helper_defs, [])]
    )

    native_int_args = tuple2_table_native_args(decl, module_name, decl_map, arg_bindings, direct_args?)

    core_body =
      cond do
        rc_required? ->
          [
            entry_probe,
            "return #{native}(out, #{native_int_args});",
            exit_probe
          ]

        true ->
          [
            entry_probe,
            "ElmcValue *tmp_result = NULL;",
            "if (#{native}(&tmp_result, #{native_int_args}) != RC_SUCCESS) return NULL;",
            exit_probe,
            "return tmp_result;"
          ]
      end

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

  defp emit_tuple2_table_function(
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
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    Process.put(
      :elmc_generic_helper_defs,
      [helper_c | Process.get(:elmc_generic_helper_defs, [])]
    )

    native_args = tuple2_table_native_args(decl, module_name, decl_map, arg_bindings, direct_args?)

    core_body = [
      entry_probe,
      if(rc_required?,
        do: "*out = #{native}(#{native_args});",
        else: "return #{native}(#{native_args});"
      ),
      exit_probe
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
            NativeFunctionCall.native_scalar_fn?(&1, mod.name, decl_map) and
            emit_native_prototype?(&1, mod.name, decl_map) and
            not Plan.primary_lowered?(&1, mod.name, decl_map) and
            not Fusion.rc_native_fusion?(mod.name, &1.name, &1.expr, decl_map))
      )
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        return_kind = NativeFunctionCall.return_kind(decl, mod.name, decl_map)
        {return_type, params} = NativeFunctionCall.native_def_signature(decl, mod.name, decl_map, return_kind)

        "static #{return_type} #{c_name}_native(#{params});"
      end)
    end)
    |> Enum.join("\n")
  end

  @spec generic_plan_native_projection_prototypes(
          ElmEx.IR.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: String.t()
  def generic_plan_native_projection_prototypes(ir, generic_targets, decl_map) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(fn decl ->
        target = {mod.name, decl.name}

        decl.kind == :function and MapSet.member?(generic_targets, target) and
          PlanNativeProjection.eligible?(decl, mod.name, decl_map)
      end)
      |> Enum.map(fn decl ->
        PlanNativeProjection.prototype(decl, mod.name, decl_map)
      end)
    end)
    |> Enum.reject(&(&1 == ""))
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
             not NativeFunctionCall.native_scalar_fn?(decl, mod.name, decl_map) or
             Plan.primary_lowered?(decl, mod.name, decl_map))
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
    fusion_native? = rc_native_fusion?(module_name, decl, decl_map)
    wrapper_arg_kinds =
      if fusion_native?,
        do: NativeFunctionCall.signature_arg_kinds(decl, module_name, decl_map),
        else: arg_kinds

    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

    wrapper_bindings =
      native_wrapper_bindings(c_arg_bindings, wrapper_arg_kinds, false)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    return_kind = NativeFunctionCall.return_kind(decl, module_name, decl_map)
    native_env = native_env(decl, module_name, function_arities, decl_map, return_kind)
    skip_native? = skip_native_def?(decl, module_name, decl_map)

    collect_generic_helpers? = return_kind == :boxed and not skip_native?

    if collect_generic_helpers? do
      Process.put(:elmc_generic_helper_defs, [])
      Process.put(:elmc_generic_helper_counter, 0)
    end

    {helper_defs, native_def} =
      if skip_native? do
        {"", ""}
      else
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
            skip_native? ->
              wrapper_return_skipped_native(
                decl,
                module_name,
                decl_map,
                c_name,
                native_args,
                return_kind,
                rc_required?
              )

            fusion_native? and return_kind == :boxed and rc_required? ->
              "return #{c_name}_native(out, #{rc_native_fusion_call_args(c_arg_bindings, wrapper_arg_kinds)});"

            fusion_native? and return_kind == :boxed ->
              """
              ElmcValue *tmp_result = NULL;
              if (#{c_name}_native(&tmp_result, #{rc_native_fusion_call_args(c_arg_bindings, wrapper_arg_kinds)}) != RC_SUCCESS) return NULL;
              return tmp_result;
              """

            rc_required? and return_kind == :boxed ->
              if NativeFunctionCall.native_boxed_rc_abi?(decl, module_name, decl_map) do
                rc_native_boxed_delegate(c_name, native_args)
              else
                rc_legacy_boxed_native_delegate(c_name, native_args)
              end

            rc_required? and return_kind == :native_int ->
              """
              RC Rc = elmc_new_int(#{RcRuntimeEmit.function_out_param()}, #{c_name}_native(#{native_args}));
              return Rc;
              """

            rc_required? and return_kind == :native_bool ->
              if NativeFunctionCall.native_bool_rc_abi?(decl, module_name, decl_map) do
                rc_native_bool_delegate(c_name, native_args)
              else
                """
                RC Rc = elmc_new_bool(out, #{c_name}_native(#{native_args}));
                return Rc;
                """
              end

            true ->
              wrapper_return(c_name, native_args, return_kind, decl, module_name, decl_map)
          end

        wrapper_unused_casts =
          unused_arg_casts(c_arg_bindings, [wrapper_bindings, return_stmt])

        wrapper_void_casts =
          if arg_names == [], do: wrapper_abi_void_casts(false, []), else: ""

        """
        #{linkage}#{signature} {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          #{wrapper_void_casts}
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

  defp rc_native_fusion?(module_name, decl, decl_map) do
    Fusion.rc_native_fusion?(module_name, decl.name, decl.expr, decl_map)
  end

  defp rc_native_fusion_call_args(c_arg_bindings, arg_kinds) do
    c_arg_bindings
    |> Enum.zip(arg_kinds)
    |> Enum.map(fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> c_arg
        :native_bool -> c_arg
        :boxed -> c_arg
      end
    end)
    |> Enum.join(", ")
  end

  defp native_wrapper_bindings(c_arg_bindings, arg_kinds, true) do
    native_wrapper_bindings(c_arg_bindings, arg_kinds, false)
  end

  defp native_wrapper_bindings(c_arg_bindings, arg_kinds, false) do
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
    RecordCompile.reset_deferred_call_operand_releases()
    RecordCompile.reset_borrowed_field_refs()

    if native_function_owned_slots?(decl, module_name, decl_map, return_kind) do
      ValueSlots.reset(epilogue_lifo: true)
    end

    case_helpers =
      if collect_generic_helpers? do
        generic_helper_defs_and_clear()
      else
        ""
      end

    unused_casts =
      unused_arg_casts(c_arg_bindings, [entry_probe, exit_probe])

    if return_kind == :boxed do
      case FunctionSplit.try_emit_native_split(
             decl,
             module_name,
             decl_map,
             native_env,
             arg_kinds,
             c_name,
             entry_probe,
             exit_probe,
             unused_casts
           ) do
        {:ok, native_def} ->
          {"", case_helpers <> native_def}

        :error ->
          compile_native_function_body_unsplit(
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
            case_helpers
          )
      end
    else
      compile_native_function_body_unsplit(
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
        case_helpers
      )
    end
  end

  defp compile_native_function_body_unsplit(
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
         case_helpers
       ) do
    if NativeFunctionCall.native_bool_rc_candidate?(decl, module_name, decl_map) do
      FunctionCallCompile.reset_call_args_cache!()
    end

    {body_code, body_var, _counter} =
      compile_native_body(decl, module_name, decl_map, native_env, return_kind, arg_kinds)

    unless return_kind == :boxed and RcRuntimeEmit.function_out_ref?(body_var),
      do: ValueSlots.track(body_var)

    deferred_release_code = RecordCompile.deferred_call_operand_release_code()

    unused_casts =
      unused_arg_casts(c_arg_bindings, [body_code, deferred_release_code, entry_probe, exit_probe, "return #{body_var};"])

    native_def =
      cond do
        return_kind == :boxed ->
          wrap_native_boxed_function_body(
            c_name,
            decl,
            module_name,
            decl_map,
            body_code,
            deferred_release_code,
            body_var,
            entry_probe,
            exit_probe,
            unused_casts,
            case_helpers
          )

        return_kind == :native_bool and
            NativeFunctionCall.native_bool_rc_candidate?(decl, module_name, decl_map) ->
          wrap_native_bool_rc_function_body(
            c_name,
            decl,
            module_name,
            decl_map,
            body_code,
            deferred_release_code,
            body_var,
            entry_probe,
            exit_probe,
            unused_casts,
            case_helpers
          )

        true ->
          """
          #{case_helpers}static #{native_return_prefix(return_kind)}#{c_name}_native(#{NativeFunctionCall.params(decl, module_name, decl_map)}) {
            #{unused_casts}
            #{entry_probe}
            #{body_code}#{deferred_release_code}
            #{exit_probe}
            return #{body_var};
          }
          """
      end

    {"", native_def}
  end

  defp wrap_native_boxed_function_body(
         c_name,
         decl,
         module_name,
         decl_map,
         body_code,
         deferred_release_code,
         body_var,
         entry_probe,
         exit_probe,
         unused_casts,
         case_helpers
       ) do
    body_text =
      [entry_probe, body_code, deferred_release_code, exit_probe]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    owned_decls = ValueSlots.owned_declaration()
    failure_cleanup = ValueSlots.failure_cleanup()

    rc_abi? = NativeFunctionCall.native_boxed_rc_candidate?(decl, module_name, decl_map)
    register_native_boxed_rc_abi!(module_name, decl.name, rc_abi?)

    needs_catch? = rc_body_needs_catch?(body_text) or owned_decls != "" or rc_abi?

    {return_type, signature_params} =
      if rc_abi? do
        params = NativeFunctionCall.params(decl, module_name, decl_map)
        {"RC", RcRuntimeEmit.native_signature_suffix("ElmcValue **out", params)}
      else
        {"ElmcValue *", NativeFunctionCall.params(decl, module_name, decl_map)}
      end

    {hoisted_decl, catch_body} =
      if needs_catch? do
        prepare_native_boxed_catch_body(body_text, body_var)
      else
        if rc_abi? do
          {"", body_text}
        else
          {"", body_text <> "\nreturn #{body_var};"}
        end
      end

    prefix =
      (if needs_catch? do
         ["RC Rc = RC_SUCCESS;"]
       else
         []
       end) ++
        List.wrap(hoisted_decl) ++
        List.wrap(owned_decls) ++
        List.wrap(unused_casts)

    catch_body_with_out =
      if needs_catch? and rc_abi? and not RcRuntimeEmit.function_out_ref?(body_var) do
        catch_body <> "\n    " <> publish_rc_function_out(body_var)
      else
        catch_body
      end

    core =
      if needs_catch? do
        """
        CATCH_BEGIN
        #{catch_body_with_out}
        CATCH_END;
        """
      else
        catch_body
      end

    suffix =
      cond do
        needs_catch? and rc_abi? ->
          """
          #{Enum.join(epilogue_suffix(failure_cleanup, catch_body_with_out, true), "\n")}
          return Rc;
          """

        needs_catch? ->
          ValueSlots.catch_return_epilogue(body_var, failure_cleanup)

        rc_abi? ->
          body_var = ValueSlots.resolve_result_slot(body_var)

          owned_transfer =
            if ValueSlots.owned_ref?(body_var), do: ValueSlots.transfer_and_null(body_var), else: ""

          """
          *out = #{body_var};
          #{owned_transfer}#{failure_cleanup}
          return RC_SUCCESS;
          """

        true ->
          ""
      end

    """
    #{case_helpers}static #{return_type} #{c_name}_native(#{signature_params}) {
      #{Enum.join(prefix, "\n")}
      #{core}
      #{suffix}
    }
    """
  end

  defp wrap_native_bool_rc_function_body(
         c_name,
         decl,
         module_name,
         decl_map,
         body_code,
         deferred_release_code,
         body_var,
         entry_probe,
         exit_probe,
         unused_casts,
         case_helpers
       ) do
    body_text =
      [entry_probe, body_code, deferred_release_code, exit_probe]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    owned_decls = ValueSlots.owned_declaration()
    failure_cleanup = ValueSlots.failure_cleanup()

    rc_abi? = NativeFunctionCall.native_bool_rc_candidate?(decl, module_name, decl_map)
    register_native_bool_rc_abi!(module_name, decl.name, rc_abi?)

    needs_catch? = rc_body_needs_catch?(body_text) or owned_decls != "" or rc_abi?

    signature_params =
      RcRuntimeEmit.native_signature_suffix(
        "bool *out",
        NativeFunctionCall.params(decl, module_name, decl_map)
      )

    {hoisted_decl, catch_body} =
      if needs_catch? do
        prepare_native_bool_catch_body(body_text, body_var)
      else
        {"", body_text <> "\n*out = #{body_var};\nreturn RC_SUCCESS;"}
      end

    prefix =
      (if needs_catch? do
         ["RC Rc = RC_SUCCESS;"]
       else
         []
       end) ++
        List.wrap(hoisted_decl) ++
        List.wrap(owned_decls) ++
        List.wrap(unused_casts)

    catch_body_with_out =
      if needs_catch? and rc_abi? do
        catch_body <> "\n    *out = #{body_var};"
      else
        catch_body
      end

    core =
      if needs_catch? do
        """
        CATCH_BEGIN
        #{catch_body_with_out}
        CATCH_END;
        """
      else
        catch_body
      end

    suffix =
      if needs_catch? and rc_abi? do
        """
        #{Enum.join(epilogue_suffix(failure_cleanup, catch_body_with_out, true), "\n")}
        return Rc;
        """
      else
        ""
      end

    """
    #{case_helpers}static RC #{c_name}_native(#{signature_params}) {
      #{Enum.join(prefix, "\n")}
      #{core}
      #{suffix}
    }
    """
  end

  defp prepare_native_bool_catch_body(body_text, body_var) do
    body_text =
      body_text
      |> String.replace("return #{body_var};", "")
      |> String.trim_trailing()

    if native_bool_result_var?(body_var) do
      bool_decl = "bool #{body_var};"
      const_assign = ~r/const\s+bool\s+#{Regex.escape(body_var)}\s*=/

      has_const_assign? = Regex.match?(const_assign, body_text)

      body_text =
        if has_const_assign? do
          Regex.replace(const_assign, body_text, "#{body_var} =")
        else
          body_text
        end

      cond do
        String.contains?(body_text, bool_decl) ->
          {bool_decl, String.replace(body_text, bool_decl, "", global: false) |> String.trim_trailing()}

        true ->
          {bool_decl, body_text}
      end
    else
      {"", body_text}
    end
  end

  defp native_bool_result_var?(ref) when is_binary(ref),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, ref)

  defp native_bool_result_var?(_), do: false

  defp prepare_native_boxed_catch_body(body_text, body_var) do
    body_text =
      body_text
      |> String.replace("return #{body_var};", "")
      |> String.trim_trailing()

    hoist_result_decl(body_text, body_var)
  end

  defp hoist_result_decl(body_text, body_var) do
    if ValueSlots.owned_ref?(body_var) or RcRuntimeEmit.function_out_ref?(body_var) do
      {"", body_text}
    else
      hoist_boxed_result_decl(body_text, body_var)
    end
  end

  defp hoist_boxed_result_decl(body_text, body_var) do
    null_decl = "ElmcValue *#{body_var} = NULL;"

    cond do
      String.contains?(body_text, null_decl) ->
        {null_decl, String.replace(body_text, null_decl, "", global: false) |> String.trim_trailing()}

      String.contains?(body_text, "ElmcValue *#{body_var};") ->
        bare_decl = "ElmcValue *#{body_var};"
        {bare_decl, String.replace(body_text, bare_decl, "", global: false) |> String.trim_trailing()}

      true ->
        {null_decl, body_text}
    end
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
    |> Map.put(:__record_field_types__, Process.get(:elmc_record_field_types, %{}))
    |> Map.put(
      :__function_analysis__,
      LetAnalysis.analyze_function_expr(
        decl.expr || %{op: :int_literal, value: 0},
        module_name,
        decl_map
      )
    )
    |> Map.put(:__native_return_kind__, return_kind)
    |> then(fn env ->
      cond do
        return_kind == :boxed and NativeFunctionCall.native_boxed_rc_candidate?(decl, module_name, decl_map) ->
          env
          |> Map.put(:__native_rc_out__, true)
          |> RcRuntimeEmit.rc_catch_env()

        return_kind == :native_bool and
            NativeFunctionCall.native_bool_rc_candidate?(decl, module_name, decl_map) ->
          env
          |> Map.put(:__native_rc_out__, true)
          |> RcRuntimeEmit.rc_catch_env()

        true ->
          env
      end
    end)
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
            expr_env =
              if Map.get(env, :__native_rc_out__) do
                env |> RecordCompile.with_subexpr_cache()
              else
                env
              end

            compile_scalar_native_expr(expr, expr_env, return_kind, 0)
        end
    end
  end
  end

  defp compile_native_body(decl, module_name, _decl_map, env, :boxed, arg_kinds) do
    c_arg_bindings = c_arg_bindings(decl.args || [])

    case compile_tail_recursive(decl, module_name, env, c_arg_bindings, arg_kinds, :boxed) do
      {:ok, code, result_var} ->
        {code, result_var, 0}

      :error ->
        env = RecordCompile.with_subexpr_cache(env)

        expr_env =
          if Map.get(env, :__native_rc_out__),
            do: RcRuntimeEmit.function_tail_env(env),
            else: env

        Host.compile_expr(decl.expr || %{op: :int_literal, value: 0}, expr_env, 0)
    end
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
    c_arg_bindings = c_arg_bindings(decl.args || [])
    compile_tail_recursive(decl, module_name, env, c_arg_bindings, arg_kinds, return_kind)
  end

  defp compile_tail_recursive(decl, module_name, env, arg_bindings, arg_kinds, return_kind) do
    arg_names = decl.args || []
    arg_types = if is_binary(decl.type), do: Host.function_arg_types(decl.type), else: []

    with true <- arg_names != [],
         true <- tail_recursive_arg_kinds?(arg_kinds, arg_types),
         {:if_tail, cond_expr, base_expr, recursive_args, recurse_on_truthy?, let_prelude} <-
           tail_recursive_if(decl.expr, module_name, decl.name),
         true <- length(recursive_args) == length(arg_names) do
      c_arg_bindings =
        case arg_bindings do
          bindings when bindings != [] -> bindings
          _ -> c_arg_bindings(arg_names)
        end

      loop_bindings =
        c_arg_bindings
        |> Enum.with_index()
        |> Enum.zip(arg_kinds)
        |> Enum.map_join("\n  ", fn {{{_arg, c_arg, _index}, index}, kind} ->
          loop = loop_arg_name(c_arg)

          case {kind, Enum.at(arg_types, index) |> Host.normalize_type_name()} do
            {:native_int, _} ->
              "elmc_int_t #{loop} = #{c_arg};"

            {:boxed, "Int"} ->
              box = boxed_int_loop_name(c_arg)
              "elmc_int_t #{loop} = elmc_as_int(#{c_arg});\n  ElmcValue *#{box} = NULL;\n  #{tail_int_box_new_stmt(box, loop, env)}"

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

          case {kind, Enum.at(arg_types, index) |> Host.normalize_type_name()} do
            {:native_int, _} ->
              EnvBindings.put_native_int_binding(acc, source_arg, loop)

            {:boxed, "Int"} ->
              box = boxed_int_loop_name(c_arg)

              acc
              |> EnvBindings.put_native_int_binding(source_arg, loop)
              |> Map.put(source_arg, box)

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
        Map.put(loop_env, :__tail_loop_invariant_refs__, MapSet.new(hoisted_refs))

      ValueSlots.push_loop()

      {cond_code, cond_ref, counter} = NativeBool.compile_expr(cond_expr, loop_env, counter)

      {base_code, base_ref, counter} =
        if return_kind == :boxed do
          Host.compile_expr(base_expr, loop_env, counter)
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
        {let_code, let_ref, ctr2} = Host.compile_expr(let_value, env, ctr)
        {Map.put(env, let_name, let_ref), ctr2, code_acc <> "\n" <> let_code}
      end)

    {_counter, update_code, int_refs, boxed_refs, boxed_int_refs} =
      recursive_args
      |> Enum.zip(c_arg_bindings)
      |> Enum.zip(arg_kinds)
      |> Enum.with_index()
      |> Enum.reduce({counter, let_code, [], [], []}, fn {{{arg_expr, {_source_arg, c_arg, _index}}, kind}, index},
                                                    {ctr, code_acc, int_refs, boxed_refs, boxed_int_refs} ->
        loop = loop_arg_name(c_arg)
        type_name = Enum.at(arg_types, index) |> Host.normalize_type_name()
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
             int_refs ++ [{loop, next_ref}], boxed_refs,
             if(kind == :boxed and type_name == "Int",
               do: boxed_int_refs ++ [{boxed_int_loop_name(c_arg), loop}],
               else: boxed_int_refs
             )}
        end
      end)

    {update_code, int_refs, boxed_refs, boxed_int_refs, loop_env}
  end

  defp effective_tail_loop_kind(:boxed, "Int"), do: :native_int
  defp effective_tail_loop_kind(kind, _type_name), do: kind

  defp compile_tail_recursive_step_arg(expr, loop_env, :boxed, counter),
    do: Host.compile_expr(expr, loop_env, counter)

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
      case {kind, Enum.at(arg_types, index) |> Host.normalize_type_name()} do
        {:native_int, _} -> true
        {:native_bool, _} -> true
        {:boxed, _} -> true
        _ -> false
      end
    end)
  end

  defp loop_arg_name(c_arg), do: "#{c_arg}_loop"

  defp boxed_int_loop_name(c_arg), do: "#{c_arg}_box_loop"

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
    releases =
      arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{{_source, c_arg, _arg_index}, kind}, index} ->
        type_name = Enum.at(arg_types, index) |> Host.normalize_type_name()

        if effective_tail_loop_kind(kind, type_name) == :boxed do
          ["elmc_release(#{loop_arg_name(c_arg)});"]
        else
          if kind == :boxed and type_name == "Int" do
            ["elmc_release(#{boxed_int_loop_name(c_arg)});"]
          else
            []
          end
        end
      end)
      |> Enum.join("\n      ")

    result_assign =
      if ValueSlots.owned_ref?(base_ref) do
        """
        #{result_var} = #{base_ref};
        #{ValueSlots.transfer_and_null(base_ref)}
        """
      else
        "#{result_var} = #{base_ref};"
      end

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

  defp register_native_boxed_rc_abi!(module_name, name, rc_abi?) do
    table = Process.get(:elmc_native_boxed_rc_abi, %{})
    Process.put(:elmc_native_boxed_rc_abi, Map.put(table, {module_name, name}, rc_abi?))
  end

  defp register_native_bool_rc_abi!(module_name, name, rc_abi?) do
    table = Process.get(:elmc_native_bool_rc_abi, %{})
    Process.put(:elmc_native_bool_rc_abi, Map.put(table, {module_name, name}, rc_abi?))
  end

  defp wrapper_return(c_name, native_args, :boxed, decl, module_name, decl_map) do
    if NativeFunctionCall.native_boxed_rc_abi?(decl, module_name, decl_map) do
      non_rc_wrapper_boxed_rc_native_delegate(c_name, native_args)
    else
      "return #{c_name}_native(#{native_args});"
    end
  end

  defp wrapper_return(c_name, native_args, :native_bool, decl, module_name, decl_map) do
    if NativeFunctionCall.native_bool_rc_abi?(decl, module_name, decl_map) do
      rc_native_bool_delegate(c_name, native_args)
    else
      wrapper_return_scalar(c_name, native_args, :native_bool)
    end
  end

  defp wrapper_return(c_name, native_args, return_kind, _decl, _module_name, _decl_map) do
    wrapper_return_scalar(c_name, native_args, return_kind)
  end

  defp native_function_owned_slots?(decl, module_name, decl_map, return_kind) do
    case return_kind do
      :boxed ->
        NativeFunctionCall.native_boxed_rc_candidate?(decl, module_name, decl_map)

      :native_bool ->
        NativeFunctionCall.native_bool_rc_candidate?(decl, module_name, decl_map)

      _ ->
        false
    end
  end

  defp rc_native_bool_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args("&native_result", native_args)})"

    """
    RC Rc = RC_SUCCESS;
    bool native_result = false;
    CATCH_BEGIN
      Rc = #{call};
      CHECK_RC(Rc);
      Rc = elmc_new_bool(out, native_result);
      CHECK_RC(Rc);
    CATCH_END;
    return Rc;
    """
    |> String.trim()
  end

  defp rc_native_boxed_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args("out", native_args)})"
    """
    RC Rc = RC_SUCCESS;
    CATCH_BEGIN
      Rc = #{call};
      CHECK_RC(Rc);
    CATCH_END;
    return Rc;
    """
    |> String.trim()
  end

  defp rc_legacy_boxed_native_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{native_args})"

    """
    RC Rc = RC_SUCCESS;
    CATCH_BEGIN
      *out = #{call};
    CATCH_END;
    return Rc;
    """
    |> String.trim()
  end

  defp non_rc_wrapper_boxed_rc_native_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args("&result", native_args)})"

    """
    RC Rc = RC_SUCCESS;
    ElmcValue *result = NULL;
    CATCH_BEGIN
      Rc = #{call};
      CHECK_RC(Rc);
    CATCH_END;
    return (Rc == RC_SUCCESS) ? result : NULL;
    """
    |> String.trim()
  end

  defp wrapper_return_scalar(c_name, native_args, :native_int) do
    """
    RC Rc = elmc_new_int(#{RcRuntimeEmit.function_out_param()}, #{c_name}_native(#{native_args}));
    return Rc;
    """
    |> String.trim()
  end

  defp wrapper_return_scalar(c_name, native_args, :native_bool) do
    """
    RC Rc = elmc_new_bool(#{RcRuntimeEmit.function_out_param()}, #{c_name}_native(#{native_args}));
    return Rc;
    """
    |> String.trim()
  end

  defp wrapper_return_skipped_native(
         decl,
         module_name,
         decl_map,
         c_name,
         native_args,
         return_kind,
         rc_required?
       ) do
    literal_expr = skipped_native_boxed_literal(decl, module_name, decl_map, return_kind, rc_required?)

    if is_binary(literal_expr) do
      literal_expr
    else
      wrapper_return(c_name, native_args, return_kind, decl, module_name, decl_map)
    end
  end

  defp skipped_native_boxed_literal(decl, module_name, decl_map, :native_int, true) do
    env = %{__module__: module_name, __program_decls__: decl_map}

    case ConstantInt.literal_value(decl.expr || %{op: :int_literal, value: 0}, env) do
      {:ok, value} ->
        "return elmc_new_int(out, #{value});"

      :error ->
        nil
    end
  end

  defp skipped_native_boxed_literal(decl, module_name, decl_map, :native_int, false) do
    env = %{__module__: module_name, __program_decls__: decl_map}

    case ConstantInt.literal_value(decl.expr || %{op: :int_literal, value: 0}, env) do
      {:ok, value} ->
        "return elmc_new_int(#{RcRuntimeEmit.function_out_param()}, #{value});"

      :error ->
        nil
    end
  end

  defp skipped_native_boxed_literal(%{expr: %{op: :bool_literal, value: value}}, _module, _decl_map, :native_bool, true) do
    c_value = if value, do: "true", else: "false"

    "return elmc_new_bool(out, #{c_value});"
  end

  defp skipped_native_boxed_literal(%{expr: %{op: :bool_literal, value: value}}, _module, _decl_map, :native_bool, false) do
    c_value = if value, do: "true", else: "false"

    "return elmc_new_bool(#{RcRuntimeEmit.function_out_param()}, #{c_value});"
  end

  defp skipped_native_boxed_literal(_decl, _module, _decl_map, _return_kind, _rc_required?), do: nil

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
