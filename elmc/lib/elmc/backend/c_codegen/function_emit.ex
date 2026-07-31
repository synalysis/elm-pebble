defmodule Elmc.Backend.CCodegen.FunctionEmit do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


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
  alias Elmc.Backend.CCodegen.RowMajorLayout
  alias Elmc.Backend.CCodegen.TailRecursiveLoopEmit
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.UnsupportedSurface
  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.FunctionCallAbi
  alias Elmc.Backend.CCodegen.FunctionSplit
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.PlanNativeProjection
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.ImmortalStaticList
  alias Elmc.Backend.Plan.Fusion.Matchers.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.CCodegen.DirectRender.Emit.RecordGetHoistPass
  alias Elmc.Backend.SizeProfile
  alias Elmc.Backend.Plan

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
    # plan_ir_mode normalizes to only :primary | :shadow, so the historical
    # non-primary native-first arms were Dialyzer-dead (Pattern false / Type true).
    # Native emit remains available via emit_native_function_def/6.
    emit_boxed_function_def(
      decl,
      module_name,
      c_name,
      function_arities,
      decl_map,
      emit_wrapper?
    )
  end

  @spec emit_argv_wrapper?(Types.decl(), String.t(), Types.decl_map(), boolean()) :: boolean()

  def emit_argv_wrapper?(decl, module_name, decl_map, emit_wrapper?) do
    emit_wrapper? and not FunctionCallAbi.direct_entry_abi?(decl, module_name, decl_map)
  end

  @spec emit_boxed_function_def(
          Types.decl(),
          String.t(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.decl_map(),
          boolean()
        ) :: String.t()

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
    Process.put(:elmc_plan_fn_noinline, false)
    direct_args? =
      FunctionCallAbi.direct_entry_abi?(decl, module_name, decl_map) or
        not worker_rc_abi?(emit_wrapper?, module_name, decl.name, decl_map)
    {immortal_prelude, body} = emit_body(decl, module_name, function_arities, decl_map, direct_args?)
    helper_defs = generic_helper_defs()
    Process.delete(:elmc_generic_helper_defs)
    Process.delete(:elmc_generic_helper_counter)

    if PlanNativeProjection.supersedes_boxed_emit?(decl, module_name, decl_map) do
      native_projection = PlanNativeProjection.emit(decl, module_name, decl_map)

      """
      #{immortal_prelude}#{if immortal_prelude == "", do: "", else: "\n"}#{helper_defs}#{native_projection}
      """
      |> String.trim_trailing()
    else
      if body == "" do
        immortal_prelude <> helper_defs
      else
    policy =
      if direct_args? do
        "#{Enum.join(decl.ownership, ", ")}, direct_call_abi"
      else
        Enum.join(decl.ownership, ", ")
      end

    rc_required? = RcRequired.rc_required?(module_name, decl.name)
    native_ret = NativeReturn.cached_kind({module_name, decl.name})
    value_return? = NativeReturn.value_return?({module_name, decl.name})

    signature =
      cond do
        value_return? and direct_args? ->
          direct_params(decl, module_name, decl_map)

        rc_required? and native_ret ->
          native_rc_function_params(direct_args?, decl, module_name, decl_map, native_ret)

        rc_required? ->
          rc_function_params(direct_args?, decl, module_name, decl_map)

        direct_args? ->
          direct_params(decl, module_name, decl_map)

        true ->
          "ElmcValue ** const args, const int argc"
      end

    return_type =
      cond do
        value_return? and native_ret -> NativeReturn.c_value_type(native_ret)
        rc_required? -> "RC"
        true -> "ElmcValue *"
      end

    linkage = function_linkage_prefix(module_name, decl.name)
    Process.put(:elmc_plan_fn_noinline, false)

    native_projection =
      if PlanNativeProjection.eligible?(decl, module_name, decl_map) do
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
    end
  end

  @spec size_fusion_native_first?(keyword() | map(), String.t(), Types.decl(), Types.decl_map()) ::
          boolean()

  def size_fusion_native_first?(opts, module_name, decl, decl_map) do
    Elmc.Backend.SizeProfile.size?(opts) and
      Fusion.rc_native_fusion?(module_name, decl.name, decl.expr, decl_map)
  end

  @spec skip_native_def?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp skip_native_def?(decl, module_name, decl_map) do
    skippable_zero_arg_native?(decl, module_name, decl_map)
  end

  @spec emit_native_prototype?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp emit_native_prototype?(decl, module_name, decl_map) do
    emit_native_function?(decl, module_name, decl_map) or
      not skippable_zero_arg_native?(decl, module_name, decl_map)
  end

  @spec skippable_zero_arg_native?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp skippable_zero_arg_native?(decl, module_name, decl_map) do
    (decl.args || []) == [] and
      not NativeFunctionCall.native_args?(decl, module_name, decl_map) and
      not ListIntSearch.recognized?(decl, module_name, decl_map) and
      not match?({:ok, _}, ListIntReduce.recognize(decl, module_name, decl_map)) and
      NativeFunctionCall.return_kind(decl, module_name, decl_map) in [:native_int, :native_bool] and
      native_zero_arg_literal_body?(decl, module_name, decl_map)
  end

  @spec native_zero_arg_literal_body?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

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

  @spec emit_native_function?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp emit_native_function?(decl, module_name, decl_map) do
    not skip_native_def?(decl, module_name, decl_map)
  end

  @spec function_linkage_prefix(String.t(), String.t()) :: String.t()
  defp function_linkage_prefix(module_name, decl_name) do
    exported? =
      Process.get(:elmc_exported_targets, MapSet.new())
      |> MapSet.member?({module_name, decl_name})

    # Large plan bodies (many CFG blocks) must not be inlined into update /
    # cornerSlots: after GuardedSwitch entry seals, those arms are live and
    # -Os was duplicating multi-KiB helpers into each caller.
    noinline? = Process.get(:elmc_plan_fn_noinline, false) == true

    cond do
      exported? -> ""
      noinline? -> "static __attribute__((noinline, noclone)) "
      true -> "static "
    end
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

    case String.trim(params) do
      "" -> "ElmcValue **out"
      "void" -> "ElmcValue **out"
      other -> "ElmcValue **out, #{other}"
    end
  end

  @spec native_rc_function_params(
          boolean(),
          Types.decl(),
          String.t(),
          Types.decl_map(),
          Elmc.Backend.C.Lower.NativeReturn.scalar_kind() | nil
        ) :: String.t()

  defp native_rc_function_params(direct_args?, decl, module_name, decl_map, native_ret) do
    out = NativeReturn.c_out_type(native_ret)

    params =
      if direct_args? do
        direct_params(decl, module_name, decl_map)
      else
        "ElmcValue ** const args, const int argc"
      end

    case String.trim(params) do
      "" -> out
      "void" -> out
      other -> out <> ", " <> other
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
    args = effective_decl_args(decl, module_name, decl_map)
    effective = Map.put(decl, :args, args)

    case c_arg_bindings(args) do
      [] ->
        "void"

      bindings ->
        kinds = NativeFunctionCall.arg_kinds(effective, module_name, decl_map)

        # Port / body-less decls can report empty arg_kinds while still having
        # effective args from the type — default those params to boxed.
        kinds =
          if length(kinds) < length(bindings) do
            bindings
            |> Enum.with_index()
            |> Enum.map(fn {_b, idx} -> Enum.at(kinds, idx, :boxed) end)
          else
            kinds
          end

        bindings
        |> Enum.zip(kinds)
        |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
          case kind do
            :native_int -> "elmc_int_t #{c_arg}"
            :native_bool -> "bool #{c_arg}"
            _ -> "ElmcValue *#{c_arg}"
          end
        end)
    end
  end

  defp unused_direct_param_casts(decl, module_name, decl_map) do
    decl
    |> effective_decl_args(module_name, decl_map)
    |> c_arg_bindings()
    |> Enum.map_join("", fn {_arg, c_arg, _idx} -> "(void)#{c_arg}; " end)
  end

  @doc false
  @spec effective_decl_args(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          [String.t()]
  def effective_decl_args(decl, module_name, decl_map) do
    case List.wrap(Map.get(decl, :args)) do
      [_ | _] = args ->
        args

      [] ->
        # elm/core aliases keep IR `args: []` while pointing at missing Kernel
        # callees. Prefer callee/delegate names, then (for alias `f = Other.g`
        # bodies only) the alias type arity so under-application curries.
        #
        # Do **not** invent params from the type when the body is already a
        # `:lambda` / thunk — those compile to 0-param make_closure values and
        # applications must go through `zero_arity_thunk_call?`.
        case delegate_param_names(decl, module_name, decl_map) do
          names when is_list(names) and names != [] ->
            names

          _ ->
            if lambda_or_thunk_body?(Map.get(decl, :expr)) do
              []
            else
              type_param_names(Map.get(decl, :type)) || []
            end
        end
    end
  end

  @spec lambda_or_thunk_body?(map() | term()) :: boolean()

  defp lambda_or_thunk_body?(%{op: :lambda}), do: true
  defp lambda_or_thunk_body?(%{op: :constructor_call}), do: true
  defp lambda_or_thunk_body?(%{op: :partial_constructor}), do: true
  defp lambda_or_thunk_body?(%{op: :make_closure}), do: true
  # Partial application CAF: `normalize = scaleTo (Quantity.float 1)`.
  defp lambda_or_thunk_body?(%{op: :qualified_call, args: [_ | _]}), do: true
  defp lambda_or_thunk_body?(%{op: :call, args: [_ | _]}), do: true
  defp lambda_or_thunk_body?(%{op: op, body: body}) when op in [:let, :letrec], do: lambda_or_thunk_body?(body)
  defp lambda_or_thunk_body?(%{op: :let_in, in_expr: body}), do: lambda_or_thunk_body?(body)
  defp lambda_or_thunk_body?(_), do: false

  @spec type_param_names(String.t() | term()) :: [String.t()] | nil

  defp type_param_names(type) when is_binary(type) do
    case TypeParsing.function_arg_types(type) do
      [_ | _] = arg_types ->
        Enum.with_index(arg_types, fn _ty, idx -> "__eff_arg_#{idx}__" end)

      _ ->
        nil
    end
  end

  defp type_param_names(_), do: nil

  @doc false
  @spec function_type_arity(Types.function_declaration()) :: non_neg_integer()
  def function_type_arity(decl) when is_map(decl) do
    case type_param_names(Map.get(decl, :type)) do
      names when is_list(names) -> length(names)
      _ -> 0
    end
  end

  @spec delegate_param_names(map() | term(), String.t() | term(), Types.decl_map() | term()) ::
          [String.t()] | nil

  defp delegate_param_names(
         %{expr: %{op: :qualified_call, target: target, args: []}} = decl,
         module_name,
         decl_map
       ) do
    ctx = %{module: module_name, decl_map: decl_map}
    {mod, name} = Elmc.Backend.Plan.Lower.Call.parse_target(target, ctx, decl_map)

    case Map.fetch(decl_map, {mod, name}) do
      {:ok, callee_decl} ->
        case Map.get(callee_decl, :args, []) do
          param_names when param_names != [] ->
            param_names

          [] ->
            delegate_param_names(callee_decl, mod, decl_map) ||
              html_map_delegate_param_names(name, callee_decl) ||
              Elmc.Backend.Plan.Lower.Platform.Web.html_element_param_names(mod, name) ||
              type_param_names(Map.get(callee_decl, :type))
        end

      :error ->
        html_map_delegate_param_names(Map.get(decl, :name), decl) ||
          Elmc.Backend.Plan.Lower.Platform.Web.html_element_param_names(mod, name)
    end
  end

  defp delegate_param_names(%{expr: %{op: :var, name: name}}, module_name, decl_map)
       when is_binary(name) do
    delegate_var_param_names(module_name, name, decl_map)
  end

  defp delegate_param_names(%{expr: %{op: :call, name: name, args: []}}, module_name, decl_map)
       when is_binary(name) do
    delegate_var_param_names(module_name, name, decl_map)
  end

  defp delegate_param_names(_, _, _), do: nil

  @spec html_map_delegate_param_names(String.t() | term(), map() | term()) :: [String.t()] | nil

  defp html_map_delegate_param_names("map", %{expr: %{op: :qualified_call, target: target, args: []}})
       when target in ["VirtualDom.map", "Elm.Kernel.VirtualDom.map", "Html.map"],
       do: ["func", "node"]

  defp html_map_delegate_param_names("map", %{expr: %{op: :html_cmd, kind: %{value: 3}}}),
       do: ["func", "node"]

  defp html_map_delegate_param_names(_, _), do: nil

  @spec delegate_var_param_names(String.t(), String.t(), Types.decl_map()) :: [String.t()] | nil

  defp delegate_var_param_names(module_name, name, decl_map) do
    case Map.fetch(decl_map, {module_name, name}) do
      {:ok, %{args: param_names}} when is_list(param_names) and param_names != [] ->
        param_names

      _ ->
        nil
    end
  end

  @doc false
  @spec delegate_call_target(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          {String.t(), String.t()} | nil
  def delegate_call_target(decl, module_name, decl_map) when is_map(decl) do
    with names when names != [] <- effective_decl_args(decl, module_name, decl_map),
         {mod, name} <- delegate_expr_target(decl, module_name, decl_map) do
      {mod, name}
    else
      _ -> nil
    end
  end

  def delegate_call_target(_, _, _), do: nil

  @spec delegate_expr_target(map() | term(), String.t() | term(), Types.decl_map() | term()) ::
          {String.t(), String.t()} | nil

  defp delegate_expr_target(%{expr: %{op: :qualified_call, target: target, args: []}}, module_name, decl_map) do
    ctx = %{module: module_name, decl_map: decl_map}

    case Elmc.Backend.Plan.Lower.Call.parse_target(target, ctx, decl_map) do
      {mod, name} when is_binary(mod) and is_binary(name) -> {mod, name}
      _ -> nil
    end
  end

  defp delegate_expr_target(%{expr: %{op: :var, name: name}}, module_name, _decl_map)
       when is_binary(name),
       do: {module_name, name}

  defp delegate_expr_target(%{expr: %{op: :call, name: name, args: []}}, module_name, _decl_map)
       when is_binary(name),
       do: {module_name, name}

  defp delegate_expr_target(_, _, _), do: nil

  @spec boxed_direct_prototype(
          Types.function_declaration(),
          String.t(),
          String.t(),
          String.t(),
          Types.function_decl_map()
        ) :: String.t()
  def boxed_direct_prototype(decl, c_name, module_name, decl_name, decl_map) do
    params = direct_params(decl, module_name, decl_map)
    native_ret = NativeReturn.cached_kind({module_name, decl_name})
    value_return? = NativeReturn.value_return?({module_name, decl_name})

    cond do
      value_return? and native_ret ->
        value_type = NativeReturn.c_value_type(native_ret)

        case params do
          "void" -> "#{value_type} #{c_name}(void);"
          other -> "#{value_type} #{c_name}(#{other});"
        end

      RcRequired.rc_required?(module_name, decl_name) ->
        out_param =
          if native_ret, do: NativeReturn.c_out_type(native_ret), else: "ElmcValue **out"

        case params do
          "void" -> "RC #{c_name}(#{out_param});"
          other -> "RC #{c_name}(#{out_param}, #{other});"
        end

      true ->
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

  @spec worker_rc_abi?(boolean(), String.t(), String.t(), Types.decl_map()) :: boolean()

  defp worker_rc_abi?(emit_wrapper?, module_name, decl_name, decl_map) do
    emit_wrapper? or RcRequired.platform_worker_rc_abi?(module_name, decl_name, decl_map)
  end

  @spec generic_helper_defs() :: String.t()

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

  @spec store_generic_helper_c(String.t()) :: :ok

  defp store_generic_helper_c(helper_c) when is_binary(helper_c) do
    Process.put(
      :elmc_generic_helper_defs,
      [CLowerFunction.cleanup_cfg_text(helper_c) | Process.get(:elmc_generic_helper_defs, [])]
    )

    :ok
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

  def emit_body(%{expr: nil} = decl, module_name, _function_arities, decl_map, direct_args?) do
    # Port decls and other body-less exports. Prefer direct params (payload/callback)
    # over argv casts when the ABI is direct — empty `ElmcValue **out, )` is invalid C.
    stub =
      cond do
        RcRequired.rc_required?(module_name, decl.name) and not direct_args? ->
          "(void)args; (void)argc; *out = elmc_int_zero(); return RC_SUCCESS;"

        RcRequired.rc_required?(module_name, decl.name) ->
          unused = unused_direct_param_casts(decl, module_name, decl_map)
          "#{unused}*out = elmc_int_zero(); return RC_SUCCESS;"

        not direct_args? ->
          "(void)args; (void)argc; return elmc_int_zero();"

        true ->
          unused = unused_direct_param_casts(decl, module_name, decl_map)
          "#{unused}return elmc_int_zero();"
      end

    {"", stub}
  end

  def emit_body(decl, module_name, function_arities, decl_map, direct_args?) do
    {"", emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?)}
  end

  @spec emit_body_immortal_or_boxed(
          Types.decl(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.decl_map(),
          boolean(),
          boolean()
        ) :: {String.t(), String.t()}

  def emit_body_immortal_or_boxed(
         decl,
         module_name,
         function_arities,
         decl_map,
         direct_args?,
         rc_required?
       ) do
    if ImmortalStaticList.zero_arg_function?(decl) do
      case ImmortalStaticList.try_emit_function_prelude_and_body(
             module_name,
             decl.name,
             decl.expr || %{op: :int_literal, value: 0},
             direct_args?,
             rc_required?
           ) do
        {:ok, prelude, body} ->
          RecordCompile.reset_borrowed_field_refs()
          {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

          body =
            format_function_body([
              entry_probe,
              body,
              exit_probe
            ])

          {prelude, body}

        :error ->
          {"", emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?)}
      end
    else
      {"", emit_boxed_body(decl, module_name, function_arities, decl_map, direct_args?)}
    end
  end

  @spec emit_boxed_body(
          Types.decl(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.decl_map(),
          boolean()
        ) :: String.t()

  defp emit_boxed_body(decl, module_name, _function_arities, decl_map, direct_args?) do
    rc_required? = RcRequired.rc_required?(module_name, decl.name)

    RecordCompile.reset_borrowed_field_refs()

    opts = Process.get(:elmc_codegen_opts, [])
    arg_names = effective_decl_args(decl, module_name, decl_map)

    arg_bindings = c_arg_bindings(arg_names)
    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)
    arg_binding_code = arg_binding_code(arg_bindings, direct_args?)

    mode = Plan.plan_ir_mode(opts)

    if mode == :shadow do
      case Plan.shadow_verify(decl, module_name, decl_map,
             Keyword.merge(compile_opts_list(opts),
               rc_required: rc_required?,
               plan_ir_raise: plan_ir_raise?(opts)
             )
           ) do
        _ -> :ok
      end
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
      {:ok, :skip_function} ->
        ""

      {:ok, body} ->
        body

      :gap ->
        record_plan_primary_fallback(module_name, decl.name)
        emit_plan_lowering_gap_body(decl, module_name, decl_map, rc_required?, direct_args?)
    end
  end

  @spec emit_plan_lowering_gap_body(Types.decl(), String.t(), Types.decl_map(), boolean(), boolean()) ::
          String.t()

  defp emit_plan_lowering_gap_body(decl, module_name, decl_map, rc_required?, direct_args?) do
    native_ret = NativeReturn.cached_kind({module_name, decl.name})
    value_return? = NativeReturn.value_return?({module_name, decl.name})

    core =
      cond do
        rc_required? ->
          "Rc = RC_ERR_UNSUPPORTED;"

        value_return? and native_ret in [:native_int, :native_bool] ->
          "return 0;"

        true ->
          "return NULL;"
      end

    if rc_required? do
      arg_names = effective_decl_args(decl, module_name, decl_map)
      arg_bindings = c_arg_bindings(arg_names)

      wrap_rc_function_body(
        arg_bindings,
        arg_binding_code(arg_bindings, direct_args?),
        [core],
        direct_args?
      )
    else
      format_function_body([
        wrapper_abi_void_casts(direct_args?, c_arg_bindings(effective_decl_args(decl, module_name, decl_map))),
        core
      ])
    end
  end

  @spec record_plan_primary_fallback(String.t(), String.t()) :: :ok

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

  @spec maybe_emit_primary_plan_body(
          Types.decl(),
          String.t(),
          Types.decl_map(),
          [Types.c_arg_binding()],
          String.t(),
          boolean(),
          boolean(),
          String.t(),
          String.t()
        ) :: {:ok, :skip_function | String.t()} | :gap

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
    lower_result = Plan.lower_function(decl, module_name, decl_map, rc_required: rc_required?)

    case lower_result do
      {:ok, %{fusion_c: fusion_c, fusion_emit: mode}}
      when is_binary(fusion_c) and fusion_c != "" and mode in [:helper_only, :public_native] ->
        if mode == :helper_only do
          case Fusion.register_rc_native_only(module_name, decl.name) do
            _ -> :ok
          end
        end

        store_generic_helper_c(fusion_c)

        {:ok, :skip_function}

      {:ok, %{fusion_c: fusion_c} = plan} when is_binary(fusion_c) and fusion_c != "" ->
        {:ok,
         emit_plan_fusion_body(
           decl,
           module_name,
           arg_bindings,
           arg_binding_code,
           direct_args?,
           plan,
           entry_probe,
           exit_probe,
           rc_required?
         )}

      {:ok, plan} ->
        result_probe = DebugProbes.result_probe(module_name, decl.name, "*out")

        # Large CFGs are shared across callers; inlining duplicates them after
        # GuardedSwitch seals made previously-dead arms reachable (APP 64KiB).
        block_count = length(Map.get(plan, :blocks, []))

        Process.put(:elmc_plan_fn_noinline, block_count >= 10)

        plan_core =
          plan
          |> CLowerFunction.emit()
          |> CLowerFunction.cleanup_cfg_text()
          |> maybe_hoist_record_gets()
          |> CLowerFunction.cleanup_cfg_text()
          |> insert_plan_result_probe(result_probe)

        unused_casts =
          unused_arg_casts(arg_bindings, [
            arg_binding_code,
            entry_probe,
            plan_core,
            exit_probe
          ])

        body =
          format_function_body(
            [
              wrapper_abi_void_casts(direct_args?, arg_bindings),
              arg_binding_code,
              unused_casts,
              entry_probe,
              plan_core,
              exit_probe
            ]
            |> Enum.reject(&(&1 == ""))
          )

        {:ok, body}

      _ ->
        :gap
    end
  end

  @spec emit_plan_fusion_body(
          Types.decl(),
          String.t(),
          [Types.c_arg_binding()],
          String.t(),
          boolean(),
          map(),
          String.t(),
          String.t(),
          boolean()
        ) :: String.t()

  defp emit_plan_fusion_body(
         decl,
         module_name,
         arg_bindings,
         arg_binding_code,
         direct_args?,
         %{fusion_c: helper_c} = plan,
         entry_probe,
         exit_probe,
         rc_required?
       ) do
    case Map.get(plan, :native_scalar_return) do
      :native_int ->
        emit_fused_native_int_scalar_wrapper_function(
          decl,
          module_name,
          arg_bindings,
          direct_args?,
          helper_c,
          entry_probe,
          exit_probe,
          arg_binding_code,
          rc_required?,
          plan
        )

      _ ->
        emit_rc_fused_native_wrapper_function(
          decl,
          module_name,
          arg_bindings,
          direct_args?,
          helper_c,
          entry_probe,
          exit_probe,
          arg_binding_code,
          rc_required?,
          Map.get(plan, :fusion_arg_kinds)
        )
    end
  end

  @spec emit_fused_native_int_scalar_wrapper_function(
          Types.decl(),
          String.t(),
          [Types.c_arg_binding()],
          boolean(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          boolean(),
          map()
        ) :: String.t()

  defp emit_fused_native_int_scalar_wrapper_function(
         decl,
         module_name,
         arg_bindings,
         direct_args?,
         helper_c,
         entry_probe,
         exit_probe,
         arg_binding_code,
         rc_required?,
         plan
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    store_generic_helper_c(helper_c)

    native_args = fused_native_call_args(decl, arg_bindings, direct_args?)

    value_return? = Map.get(plan, :native_scalar_value_return) == true

    core_body =
      if value_return? do
        [
          entry_probe,
          "return #{native}(#{native_args});",
          exit_probe
        ]
      else
        [
          entry_probe,
          "*out = #{native}(#{native_args});",
          "return RC_SUCCESS;",
          exit_probe
        ]
      end

    if value_return? or not rc_required? do
      unused_casts = unused_arg_casts(arg_bindings, core_body)

      format_function_body(
        [wrapper_abi_void_casts(direct_args?, arg_bindings), arg_binding_code, unused_casts |
           core_body]
      )
    else
      wrap_rc_function_body(
        arg_bindings,
        arg_binding_code,
        core_body,
        direct_args?
      )
    end
  end

  @spec compile_opts_list(keyword() | map()) :: keyword()

  defp compile_opts_list(opts) when is_list(opts), do: opts
  defp compile_opts_list(opts) when is_map(opts), do: Map.to_list(opts)

  @spec plan_ir_raise?(keyword() | map()) :: boolean()

  defp plan_ir_raise?(opts) when is_list(opts), do: Keyword.get(opts, :plan_ir_raise, false)
  defp plan_ir_raise?(opts) when is_map(opts), do: Map.get(opts, :plan_ir_raise, false)

  @spec maybe_hoist_record_gets(String.t()) :: String.t()

  defp maybe_hoist_record_gets(body) when is_binary(body) do
    opts = Process.get(:elmc_codegen_opts, %{})

    if SizeProfile.size?(opts) do
      RecordGetHoistPass.run(body)
    else
      body
    end
  end

  @spec insert_plan_result_probe(String.t(), String.t()) :: String.t()

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

  @spec wrap_rc_function_body(
          [Types.c_arg_binding()],
          String.t(),
          String.t() | [String.t()],
          boolean()
        ) :: String.t()

  defp wrap_rc_function_body(
         arg_bindings,
         arg_binding_code,
         core_body,
         direct_args?
       ) do
    body_text = Enum.join(List.wrap(core_body), "\n")
    ValueSlots.ensure_covers_owned_refs(body_text)
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
        ["", "CATCH_BEGIN"] ++ [body_text] ++ ["CATCH_END", ""]
      else
        ["" , body_text, ""]
      end

    format_rc_function_body(prefix ++ core ++ suffix)
  end

  @spec rc_body_needs_catch?(String.t()) :: boolean()

  defp rc_body_needs_catch?(body_text) when is_binary(body_text) do
    String.contains?(body_text, "CHECK_RC") or
      String.contains?(body_text, "CHECK_RC_TO") or
      String.contains?(body_text, "\nbreak;")
  end

  @spec epilogue_suffix(String.t(), String.t(), boolean()) :: [String.t()]

  defp epilogue_suffix(failure_cleanup, _body_text, _needs_catch?) do
    if failure_cleanup == "", do: [], else: [failure_cleanup]
  end

  @spec publish_rc_function_out(String.t()) :: String.t()

  defp publish_rc_function_out(result_var) do
    RcRuntimeEmit.publish_function_out_from(result_var)
  end

  @spec format_rc_function_body([String.t() | iolist()]) :: String.t()

  defp format_rc_function_body(parts) do
    parts
    |> List.flatten()
    |> Enum.join("\n")
    |> CSource.format_block(2)
  end

  @spec arg_binding_code([Types.c_arg_binding()], boolean()) :: String.t()

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

  @spec wrapper_abi_void_casts(boolean(), [Types.c_arg_binding()]) :: String.t()

  defp wrapper_abi_void_casts(true, _arg_bindings), do: ""

  defp wrapper_abi_void_casts(_direct_args?, arg_bindings) when arg_bindings == [] do
    "(void)args;\n(void)argc;"
  end

  defp wrapper_abi_void_casts(_direct_args?, _arg_bindings), do: ""

  @spec format_function_body([String.t() | iolist()]) :: String.t()

  defp format_function_body(parts) do
    parts
    |> List.flatten()
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join("\n")
    |> CSource.format_block(2)
  end

  @spec emit_rc_fused_native_wrapper_function(
          Types.decl(),
          String.t(),
          [Types.c_arg_binding()],
          boolean(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          boolean(),
          [atom()] | nil
        ) :: String.t()

  defp emit_rc_fused_native_wrapper_function(
         decl,
         module_name,
         arg_bindings,
         direct_args?,
         helper_c,
         entry_probe,
         exit_probe,
         arg_binding_code,
         rc_required?,
         fusion_arg_kinds
       ) do
    c_name = Util.module_fn_name(module_name, decl.name)
    native = "#{c_name}_native"

    decl_map = Process.get(:elmc_program_decls, %{})

    fusion_kinds =
      fusion_arg_kinds ||
        Fusion.rc_native_fusion_arg_kinds({module_name, decl.name}) ||
        Fusion.infer_native_tag_fusion_arg_kinds(helper_c, decl) ||
        NativeFunctionCall.signature_arg_kinds(decl, module_name, decl_map)

    if is_list(fusion_kinds) do
      Fusion.register_rc_native_arg_kinds(module_name, decl.name, fusion_kinds)
    end

    binding_code =
      cond do
        direct_args? ->
          ""

        is_list(fusion_kinds) and
            Enum.all?(fusion_kinds, &(&1 in [:native_int, :native_bool, :boxed_int_tag, :boxed])) ->
          native_wrapper_bindings(arg_bindings, fusion_kinds)

        true ->
          arg_binding_code
      end

    # Only true when the wrapper introduced unboxed locals (`elmc_as_int` bindings).
    # `direct_args?` alone is not enough: direct-entry public params may still be
    # `ElmcValue *` while `_native` expects `elmc_int_t` (e.g. list_indexed_replace).
    # Per-arg peel vs pass-through is decided in `rc_native_fusion_call_args/7`
    # from `NativeFunctionCall.arg_kinds/3` under direct entry.
    wrapper_args_unboxed? = binding_code != ""

    fused_args =
      rc_native_fusion_call_args(
        arg_bindings,
        fusion_kinds,
        wrapper_args_unboxed?,
        module_name,
        decl.name,
        decl,
        decl_map
      )

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

    store_generic_helper_c(helper_c)

    unused_casts = unused_arg_casts(arg_bindings, core_body)

    format_function_body(
      [wrapper_abi_void_casts(direct_args?, arg_bindings), binding_code, unused_casts |
         core_body]
    )
  end

  @spec rc_native_fusion_call_args(
          [Types.c_arg_binding()],
          [atom()] | nil,
          boolean(),
          String.t(),
          String.t(),
          Types.decl(),
          Types.decl_map()
        ) :: String.t()

  defp rc_native_fusion_call_args(arg_bindings, kinds, unboxed_in_wrapper?, module_name, _fun_name, decl, decl_map)
       when is_list(kinds) do
    direct_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)

    direct_entry? = FunctionCallAbi.direct_entry_abi?(decl, module_name, decl_map)

    arg_bindings
    |> Enum.zip(kinds)
    |> Enum.map_join(", ", fn {{_arg, c_arg, index}, kind} ->
      direct_native? =
        case kind do
          :boxed_int_tag ->
            unboxed_in_wrapper? and not direct_entry?

          _ ->
            unboxed_in_wrapper? or
              (direct_entry? and Enum.at(direct_kinds, index) in [:native_int, :native_bool])
        end

      fusion_native_call_arg(c_arg, kind, direct_native?)
    end)
  end

  defp rc_native_fusion_call_args(arg_bindings, _kinds, _unboxed_in_wrapper?, _module_name, _fun_name, _decl, _decl_map) do
    arg_bindings
    |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
    |> Enum.join(", ")
  end

  @spec fusion_native_call_arg(String.t(), atom(), boolean()) :: String.t()

  defp fusion_native_call_arg(c_arg, kind, direct_native?) do
    case kind do
      :boxed_int_tag when direct_native? -> c_arg
      :boxed_int_tag -> RowMajorLayout.union_tag_expr(c_arg)
      :native_int when direct_native? -> c_arg
      :native_int -> "elmc_as_int(#{c_arg})"
      :native_bool when direct_native? -> c_arg
      :native_bool -> "elmc_as_bool(#{c_arg})"
      _ -> c_arg
    end
  end

  @spec fusion_wrapper_native_args?([atom()]) :: boolean()

  defp fusion_wrapper_native_args?(kinds) when is_list(kinds) do
    Enum.all?(kinds, &(&1 in [:native_int, :native_bool, :boxed_int_tag]))
  end

  @spec fusion_wrapper_unboxed_in_wrapper?(Types.decl(), String.t(), Types.decl_map(), [atom()]) ::
          boolean()

  defp fusion_wrapper_unboxed_in_wrapper?(decl, module_name, decl_map, wrapper_arg_kinds) do
    fusion_wrapper_native_args?(wrapper_arg_kinds) and
      not FunctionCallAbi.direct_entry_abi?(decl, module_name, decl_map)
  end

  @spec fused_native_call_args(map() | Types.decl(), [Types.c_arg_binding()], boolean()) :: String.t()

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

  @spec native_scalar_call_arg(String.t(), atom(), boolean()) :: String.t()

  defp native_scalar_call_arg(c_arg, :native_int, true), do: c_arg
  defp native_scalar_call_arg(c_arg, :native_bool, true), do: c_arg
  defp native_scalar_call_arg(c_arg, :native_int, false), do: "elmc_as_int(#{c_arg})"
  defp native_scalar_call_arg(c_arg, :native_bool, false), do: "elmc_as_bool(#{c_arg})"
  defp native_scalar_call_arg(c_arg, _kind, _direct_args?), do: c_arg

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

  @spec generic_rc_native_fusion_prototypes(
          ElmEx.IR.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: String.t()
  def generic_rc_native_fusion_prototypes(ir, generic_targets, _decl_map) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(fn decl ->
        target = {mod.name, decl.name}

        decl.kind == :function and MapSet.member?(generic_targets, target) and
          Fusion.rc_native_fusion_arg_kinds(target) != nil
      end)
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        kinds = Fusion.rc_native_fusion_arg_kinds({mod.name, decl.name})
        params = rc_native_fusion_proto_params(decl, kinds, mod.name)

        "static RC #{c_name}_native(#{params});"
      end)
    end)
    |> Enum.join("\n")
  end

  @spec rc_native_fusion_proto_params(Types.decl(), [atom()], String.t()) :: String.t()

  defp rc_native_fusion_proto_params(decl, kinds, _module_name) when is_list(kinds) do
    arg_bindings = c_arg_bindings(Map.get(decl, :args, []))

    params =
      arg_bindings
      |> Enum.zip(kinds)
      |> Enum.map(fn
        {{_arg, c_arg, _index}, :native_int} -> "elmc_int_t #{c_arg}"
        {{_arg, c_arg, _index}, :boxed_int_tag} -> "elmc_int_t #{c_arg}"
        {{_arg, c_arg, _index}, _} -> "ElmcValue *#{c_arg}"
      end)

    (["ElmcValue **out"] ++ params) |> Enum.join(", ")
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

  @spec prelower_plan_native_returns(ElmEx.IR.t(), MapSet.t(Types.function_decl_key()), Types.function_decl_map()) ::
          :ok
  def prelower_plan_native_returns(ir, generic_targets, decl_map) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(fn decl ->
        decl.kind == :function and MapSet.member?(generic_targets, {mod.name, decl.name})
      end)
      |> Enum.map(&{mod, &1})
    end)
    |> Enum.chunk_every(16)
    |> Enum.each(fn batch ->
      Enum.each(batch, fn {mod, decl} ->
        Plan.primary_lowered?(decl, mod.name, decl_map)
      end)

      :erlang.garbage_collect()
    end)

    :ok
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
          not helper_only_fusion_plan?(decl, mod.name, decl_map) and
          not PlanNativeProjection.supersedes_boxed_emit?(decl, mod.name, decl_map) and
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

  @spec helper_only_fusion_plan?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp helper_only_fusion_plan?(decl, module_name, decl_map) do
    case Plan.lower_function(decl, module_name, decl_map, rc_required?: true) do
      {:ok, %{fusion_emit: :helper_only}} -> true
      _ -> false
    end
  end

  @spec c_arg_bindings([String.t()]) :: [Types.c_arg_binding()]
  def c_arg_bindings(arg_names) do
    arg_names
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      c_arg =
        cond do
          not is_binary(arg) or not c_identifier?(arg) -> "_arg_#{index}"
          arg == "_" -> "_unused_#{index}"
          c_reserved_binding_name?(arg) -> "#{arg}_arg"
          Enum.count(arg_names, &(&1 == arg)) > 1 -> "#{arg}_#{index}"
          true -> arg
        end

      {arg, c_arg, index}
    end)
  end

  @spec c_identifier?(String.t()) :: boolean()

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

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

  @spec put_var_type(Types.compile_env(), String.t(), String.t()) :: Types.compile_env()

  defp put_var_type(env, name, type), do: EnvBindings.put_var_type(env, name, type)

  @spec emit_native_function_def(
          Types.function_declaration(),
          String.t(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          boolean()
        ) :: String.t()
  # Public so size/native-first tooling can still call this after
  # emit_function_def/6 always takes the boxed (plan-primary) path.
  def emit_native_function_def(
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
    tuple2_table? = fusion_native? and Tuple2CaseTable.recognized?(module_name, decl.name, decl.expr)

    wrapper_arg_kinds =
      cond do
        tuple2_table? ->
          List.duplicate(:native_int, length(arg_names))

        fusion_native? ->
          Fusion.rc_native_fusion_arg_kinds({module_name, decl.name}) ||
            NativeFunctionCall.signature_arg_kinds(decl, module_name, decl_map)

        true ->
          arg_kinds
      end

    if tuple2_table? do
      Fusion.register_rc_native_arg_kinds(module_name, decl.name, wrapper_arg_kinds)
    end

    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

    wrapper_bindings =
      native_wrapper_bindings(c_arg_bindings, wrapper_arg_kinds)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    return_kind = NativeFunctionCall.return_kind(decl, module_name, decl_map)
    native_env = native_env(decl, module_name, function_arities, decl_map, return_kind)
    skip_native? = skip_native_def?(decl, module_name, decl_map)

    # Fusion / native-arg helpers with a boxed return keep `ElmcValue **out`.
    # Clear NativeReturn's scalar cache so plan call sites match that ABI.
    if return_kind == :boxed and RcRequired.rc_required?(module_name, decl.name) do
      register_native_boxed_rc_abi!(module_name, decl.name, true)
    end

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
              fusion_wrapper_args =
                rc_native_fusion_call_args(
                  c_arg_bindings,
                  wrapper_arg_kinds,
                  fusion_wrapper_unboxed_in_wrapper?(decl, module_name, decl_map, wrapper_arg_kinds),
                  module_name,
                  decl.name,
                  decl,
                  decl_map
                )

              "return #{c_name}_native(out, #{fusion_wrapper_args});"

            fusion_native? and return_kind == :boxed ->
              fusion_wrapper_args =
                rc_native_fusion_call_args(
                  c_arg_bindings,
                  wrapper_arg_kinds,
                  fusion_wrapper_unboxed_in_wrapper?(decl, module_name, decl_map, wrapper_arg_kinds),
                  module_name,
                  decl.name,
                  decl,
                  decl_map
                )

              """
              ElmcValue *tmp_result = NULL;
              if (#{c_name}_native(&tmp_result, #{fusion_wrapper_args}) != RC_SUCCESS) return NULL;
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

  @spec native_boxed_special_emit(String.t(), Types.decl(), Types.decl_map()) ::
          {:ok, String.t(), list(), :rc_native}
          | {:ok, String.t(), list()}
          | :error

  defp native_boxed_special_emit(module_name, decl, decl_map) do
    case Fusion.try_emit(module_name, decl.name, decl.expr, decl_map) do
      {:ok, helper_c, callees, :rc_native} -> {:ok, helper_c, callees, :rc_native}
      {:ok, helper_c, callees} -> {:ok, helper_c, callees}
      :error -> :error
    end
  end

  @spec rc_native_fusion?(String.t(), Types.decl(), Types.decl_map()) :: boolean()

  defp rc_native_fusion?(module_name, decl, decl_map) do
    Fusion.rc_native_fusion?(module_name, decl.name, decl.expr, decl_map)
  end

  @spec native_wrapper_bindings([Types.c_arg_binding()], [atom()]) :: String.t()
  defp native_wrapper_bindings(c_arg_bindings, arg_kinds) do
    c_arg_bindings
    |> Enum.zip(arg_kinds)
    |> Enum.map_join("\n  ", fn {{_arg, c_arg, index}, kind} ->
      case kind do
        :native_int ->
          "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"

        :native_bool ->
          "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_bool(args[#{index}]) : 0;"

        :boxed_int_tag ->
          "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? #{RowMajorLayout.union_tag_expr("args[#{index}]")} : 0;"

        :boxed ->
          "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end
    end)
  end

  @spec compile_native_function_body(
          Types.decl(),
          String.t(),
          String.t(),
          Types.decl_map(),
          Types.compile_env(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          [atom()],
          [Types.c_arg_binding()],
          String.t(),
          String.t(),
          boolean()
        ) :: {String.t(), String.t()}

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

  @spec compile_native_function_body_unsplit(
          Types.decl(),
          String.t(),
          String.t(),
          Types.decl_map(),
          Types.compile_env(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          [atom()],
          [Types.c_arg_binding()],
          String.t(),
          String.t(),
          String.t()
        ) :: {String.t(), String.t()}

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

  @spec wrap_native_boxed_function_body(
          String.t(),
          Types.decl(),
          String.t(),
          Types.decl_map(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()

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
        CATCH_END
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

  @spec wrap_native_bool_rc_function_body(
          String.t(),
          Types.decl(),
          String.t(),
          Types.decl_map(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()

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
        CATCH_END
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

  @spec prepare_native_bool_catch_body(String.t(), String.t()) :: {String.t(), String.t()}

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

  @spec native_bool_result_var?(String.t()) :: boolean()

  defp native_bool_result_var?(ref) when is_binary(ref),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, ref)

  @spec prepare_native_boxed_catch_body(String.t(), String.t()) :: {String.t(), String.t()}

  defp prepare_native_boxed_catch_body(body_text, body_var) do
    body_text =
      body_text
      |> String.replace("return #{body_var};", "")
      |> String.trim_trailing()

    hoist_result_decl(body_text, body_var)
  end

  @spec hoist_result_decl(String.t(), String.t()) :: {String.t(), String.t()}

  defp hoist_result_decl(body_text, body_var) do
    if ValueSlots.owned_ref?(body_var) or RcRuntimeEmit.function_out_ref?(body_var) do
      {"", body_text}
    else
      hoist_boxed_result_decl(body_text, body_var)
    end
  end

  @spec hoist_boxed_result_decl(String.t(), String.t()) :: {String.t(), String.t()}

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

  @spec generic_helper_defs_and_clear() :: String.t()

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

  @spec compile_native_body(
          Types.decl(),
          String.t(),
          Types.decl_map(),
          Types.compile_env(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          [atom()]
        ) :: Types.compile_result()

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
            case TailRecursiveLoopEmit.compile(
                   decl,
                   module_name,
                   env,
                   c_arg_bindings(decl.args || []),
                   arg_kinds,
                   return_kind
                 ) do
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

    case TailRecursiveLoopEmit.compile(
           decl,
           module_name,
           env,
           c_arg_bindings,
           arg_kinds,
           :boxed
         ) do
      {:ok, code, result_var} ->
        {code, result_var, 0}

      :error ->
        UnsupportedSurface.record_expr(%{
          kind: :expr,
          op: :native_boxed_body,
          detail: "native boxed body lowering retired under plan-primary"
        })

        next = 0 + 1
        var = "tmp_#{next}"
        {"ElmcValue *#{var} = elmc_int_zero();", var, next}
    end
  end

  @spec compile_list_int_search_native(
          Types.decl(),
          String.t(),
          Types.decl_map(),
          Types.compile_env(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind()
        ) :: {:ok, String.t(), String.t()} | :error

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

  @spec compile_list_int_reduce_native(
          Types.decl(),
          String.t(),
          Types.decl_map(),
          Types.compile_env(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind()
        ) :: {:ok, String.t(), String.t()} | :error

  defp compile_list_int_reduce_native(decl, module_name, decl_map, env, return_kind) do
    with {:ok, spec} <- ListIntReduce.recognize(decl, module_name, decl_map),
         {:ok, code, result_var} <-
           ListIntReduce.compile(spec, env, return_kind, &compile_scalar_native_expr/4) do
      {:ok, code, result_var}
    else
      _ -> :error
    end
  end

  @spec compile_scalar_native_expr(
          Types.expr(),
          Types.compile_env(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          Types.compile_counter()
        ) :: Types.native_scalar_compile_result()

  defp compile_scalar_native_expr(expr, env, :native_int, counter),
    do: NativeInt.compile_expr(expr, env, counter)

  defp compile_scalar_native_expr(expr, env, :native_bool, counter),
    do: NativeBool.compile_expr(expr, env, counter)

  @spec register_native_boxed_rc_abi!(String.t(), String.t(), boolean()) :: :ok

  defp register_native_boxed_rc_abi!(module_name, name, rc_abi?) do
    table = Process.get(:elmc_native_boxed_rc_abi, %{})
    Process.put(:elmc_native_boxed_rc_abi, Map.put(table, {module_name, name}, rc_abi?))

    # Public ABI is `ElmcValue **out` — drop any optimistic NativeReturn scalar
    # cache so later call sites do not emit `elmc_int_t *out` arguments.
    if rc_abi? do
      NativeReturn.uncache_scalar_return(module_name, name)
    end

    :ok
  end

  @spec register_native_bool_rc_abi!(String.t(), String.t(), boolean()) :: :ok

  defp register_native_bool_rc_abi!(module_name, name, rc_abi?) do
    table = Process.get(:elmc_native_bool_rc_abi, %{})
    Process.put(:elmc_native_bool_rc_abi, Map.put(table, {module_name, name}, rc_abi?))
    :ok
  end

  @spec wrapper_return(
          String.t(),
          String.t(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          Types.decl(),
          String.t(),
          Types.decl_map()
        ) :: String.t()

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

  @spec native_function_owned_slots?(Types.decl(), String.t(), Types.decl_map(), atom()) :: boolean()

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

  @spec rc_native_bool_delegate(String.t(), String.t()) :: String.t()

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
    CATCH_END
    return Rc;
    """
    |> String.trim()
  end

  @spec rc_native_boxed_delegate(String.t(), String.t()) :: String.t()

  defp rc_native_boxed_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args("out", native_args)})"
    """
    RC Rc = RC_SUCCESS;
    CATCH_BEGIN
      Rc = #{call};
      CHECK_RC(Rc);
    CATCH_END
    return Rc;
    """
    |> String.trim()
  end

  @spec rc_legacy_boxed_native_delegate(String.t(), String.t()) :: String.t()

  defp rc_legacy_boxed_native_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{native_args})"

    """
    RC Rc = RC_SUCCESS;
    CATCH_BEGIN
      *out = #{call};
    CATCH_END
    return Rc;
    """
    |> String.trim()
  end

  @spec non_rc_wrapper_boxed_rc_native_delegate(String.t(), String.t()) :: String.t()

  defp non_rc_wrapper_boxed_rc_native_delegate(c_name, native_args) do
    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args("&result", native_args)})"

    """
    RC Rc = RC_SUCCESS;
    ElmcValue *result = NULL;
    CATCH_BEGIN
      Rc = #{call};
      CHECK_RC(Rc);
    CATCH_END
    return (Rc == RC_SUCCESS) ? result : NULL;
    """
    |> String.trim()
  end

  @spec wrapper_return_scalar(
          String.t(),
          String.t(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind()
        ) :: String.t()

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

  @spec wrapper_return_skipped_native(
          Types.decl(),
          String.t(),
          Types.decl_map(),
          String.t(),
          String.t(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          boolean()
        ) :: String.t()

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

  @spec skipped_native_boxed_literal(
          Types.decl() | map(),
          String.t(),
          Types.decl_map(),
          Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind(),
          boolean()
        ) :: String.t() | nil

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

  @spec native_return_prefix(Elmc.Backend.CCodegen.Native.FunctionCall.native_return_kind()) :: String.t()

  defp native_return_prefix(return_kind), do: "#{NativeFunctionCall.c_return_type(return_kind)} "

  @doc false
  @spec unused_arg_casts([{String.t(), String.t(), non_neg_integer()}], iolist()) :: String.t()
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

  @spec arg_referenced?(String.t(), String.t()) :: boolean()

  defp arg_referenced?(c_arg, body_text) do
    Regex.match?(~r/(?:\W|^)#{Regex.escape(c_arg)}(?:\W|$)/, body_text)
  end
end
