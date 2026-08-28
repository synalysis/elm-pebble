defmodule Elmc.Backend.Plan.Lower.Function do
  @moduledoc """
  Lower a whole function declaration expr to `%FunctionPlan{}`.
  """
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.Plan.Fusion
  alias Elmc.Backend.Plan.{Builder, Context, EpilogueRelease, Optimize, ParamFieldInference, ThinDelegate, TupleParamBind, Verify}
  alias Elmc.Backend.Plan.Lower.{Expr, Intrinsics, Platform.Web}
  alias Elmc.Backend.Plan.Types

  @spec lower(Types.function_decl(), String.t(), Types.function_decl_map(), keyword()) ::
          Types.lower_result()
  def lower(decl, module_name, decl_map, opts \\ []) do
    try do
      do_lower(decl, module_name, decl_map, opts)
    rescue
      FunctionClauseError ->
        expr = Map.get(decl, :expr) || %{}
        op = Map.get(expr, :op)
        name = Map.get(decl, :name, "anon")

        cache = Process.get(:elmc_plan_unsupported_reasons, %{})

        reason = %{
          op: op,
          error: :function_clause,
          target: Map.get(expr, :target) || Map.get(expr, :name)
        }

        Process.put(:elmc_plan_unsupported_reasons, Map.put_new(cache, {module_name, name}, reason))

        :unsupported
    end
  end

  @spec codegen_opts(keyword()) :: keyword()

  defp codegen_opts(opts) do
    Process.get(:elmc_codegen_opts, %{})
    |> Map.merge(Map.new(List.wrap(opts)))
    |> Map.to_list()
  end

  @spec do_lower(Types.decl(), String.t(), Types.decl_map(), keyword()) :: Types.lower_result()

  defp do_lower(decl, module_name, decl_map, opts) do
    opts = codegen_opts(opts)

    if Keyword.get(opts, :stream_mode) do
      lower_stream_body(decl, module_name, decl_map, opts)
    else
      do_lower_primary(decl, module_name, decl_map, opts)
    end
  end

  defp do_lower_primary(decl, module_name, decl_map, opts) do
    # Call sites read arity from decl_map. Sync partial Html.map bindings
    # (`wrap = Html.map f`) to 1-arg so callers use call_fn, not CAF+closure.
    decl_map = Web.rewrite_decl_map(decl_map, opts)
    decl = Web.rewrite_function_decl(module_name, decl, opts)

    case Fusion.try_plan(module_name, decl, decl_map, opts) do
      {:ok, plan} ->
        accept_or_fallback_fusion(plan, decl, module_name, decl_map, opts)

      :error ->
        case Intrinsics.try_lower(decl, module_name, decl_map, opts) do
          {:ok, plan} ->
            {:ok, plan}

          :not_intrinsic ->
            lower_expr_body(decl, module_name, decl_map, opts)
        end
    end
  end

  @spec register_fusion_native_cache(Types.function_plan() | map(), String.t()) ::
          Types.function_plan() | map()

  defp accept_or_fallback_fusion(plan, decl, module_name, decl_map, opts) do
    case Verify.run(plan) do
      :ok ->
        {:ok, register_fusion_native_cache(plan, module_name)}

      {:error, :unverified_fusion_c, _} ->
        case Intrinsics.try_lower(decl, module_name, decl_map, opts) do
          {:ok, ssa} ->
            {:ok, attach_fusion_sidecar(ssa, plan)}

          :not_intrinsic ->
            case lower_expr_body(decl, module_name, decl_map, opts) do
              {:ok, ssa} -> {:ok, attach_fusion_sidecar(ssa, plan)}
              other -> other
            end
        end

      {:error, reason, meta} ->
        {:error, {:verify, reason, meta}}
    end
  end

  defp attach_fusion_sidecar(ssa, fusion_plan) do
    # Verify rejects fusion_c-only as a standalone plan. Keep the C helper as an
    # emit sidecar so ListIndexedReplace / permute-merge / list-search still
    # produce `_native` bodies after the verified SSA fallback exists.
    ssa
    |> Map.put(:fusion_kind, Map.get(fusion_plan, :fusion_kind))
    |> Map.put(:fusion_data, Map.get(fusion_plan, :fusion_data))
    |> Map.put(:fusion_c, Map.get(fusion_plan, :fusion_c))
    |> Map.put(:fusion_emit, Map.get(fusion_plan, :fusion_emit))
    |> Map.put(:fusion_arg_kinds, Map.get(fusion_plan, :fusion_arg_kinds))
    |> Map.put(
      :native_scalar_return,
      Map.get(fusion_plan, :native_scalar_return) || Map.get(ssa, :native_scalar_return)
    )
    |> Map.put(
      :native_scalar_value_return,
      Map.get(ssa, :native_scalar_value_return) == true or
        Map.get(fusion_plan, :native_scalar_value_return) == true
    )
    |> then(&register_fusion_native_cache(&1, Map.get(&1, :module)))
  end

  defp register_fusion_native_cache(%{fusion_c: c, native_scalar_return: kind} = plan, module_name)
       when is_binary(c) and kind in [:native_int, :native_bool, :native_float] do
    NativeReturn.cache_scalar_return(module_name, plan.name, kind)

    if Map.get(plan, :native_scalar_value_return) == true do
      NativeReturn.cache_scalar_value_return(module_name, plan.name)
    end

    plan
  end

  defp register_fusion_native_cache(plan, _module_name), do: plan

  @spec lower_stream_body(Types.decl(), String.t(), Types.decl_map(), keyword()) :: Types.lower_result()

  defp lower_stream_body(decl, module_name, decl_map, _opts) do
    expr = Map.get(decl, :expr) || %{op: :int_literal, value: 0}
    args = Map.get(decl, :args, []) |> List.wrap()
    name = Map.get(decl, :name, "anon")

    set = Process.get(:elmc_rc_required, MapSet.new())
    Process.put(:elmc_rc_required, MapSet.put(set, {module_name, name}))

    ctx =
      Context.new(
        module: module_name,
        function_name: name,
        decl_map: decl_map,
        params: args,
        rc_required: true,
        fallible: true,
        function_tail: false,
        stream_mode: true
      )
      |> seed_param_types(decl)
      |> seed_inferred_param_fields(decl)

    b =
      Builder.new(module_name, name,
        args: args,
        rc_required: true,
        fallible: true
      )

    b_entry = preload_params(b, args)

    case TupleParamBind.bind(decl, ctx, b_entry) do
      {:ok, ctx1, b1} ->
        case Expr.compile(expr, ctx1, b1) do
          {:ok, :stream_void, b2} ->
            b3 = Builder.emit_ret(b2, :stream_void)

            plan =
              Builder.to_function_plan(b3)
              |> Map.put(:stream_mode, true)
              |> EpilogueRelease.run()
              |> Optimize.run()
              |> EpilogueRelease.run()

            case Verify.run(plan) do
              :ok -> {:ok, plan}
              {:error, reason, meta} -> {:error, {:verify, reason, meta}}
            end

          {:ok, _result_reg, _} ->
            record_plan_unsupported(module_name, name, expr)
            :unsupported

          :unsupported ->
            record_plan_unsupported(module_name, name, expr)
        end

      :unsupported ->
        record_plan_unsupported(module_name, name, expr)
    end
  end

  @spec lower_expr_body(Types.decl(), String.t(), Types.decl_map(), keyword()) ::
          Types.lower_result()

  defp lower_expr_body(decl, module_name, decl_map, opts) do
    expr = Map.get(decl, :expr) || %{op: :int_literal, value: 0}
    args = Map.get(decl, :args, []) |> List.wrap()
    name = Map.get(decl, :name, "anon")
    rc_required? = Keyword.get(opts, :rc_required, RcRequired.rc_required?(module_name, name))

    # Unit tests / isolated lowers pass `rc_required: true` without running
    # RcRequired.analyze. Seed the process set so recursive native-scalar call
    # sites pick the `RC fn(T *out, …)` ABI consistently with the plan body.
    if rc_required? do
      set = Process.get(:elmc_rc_required, MapSet.new())
      Process.put(:elmc_rc_required, MapSet.put(set, {module_name, name}))
    end

    ctx =
      Context.new(
        module: module_name,
        function_name: name,
        decl_map: decl_map,
        params: args,
        rc_required: rc_required?,
        fallible: true,
        function_tail: function_tail_compile?(decl, module_name, decl_map, rc_required?)
      )
      |> seed_param_types(decl)
      |> seed_inferred_param_fields(decl)

    b = Builder.new(module_name, name,
      args: args,
      rc_required: rc_required?,
      fallible: true
    )

    b_entry = preload_params(b, args)

    case TupleParamBind.bind(decl, ctx, b_entry) do
      {:ok, ctx1, b1} ->
        case Expr.compile(expr, ctx1, b1) do
          {:ok, result_reg, b2} ->
            {b3, ret_reg} = finalize_result(b2, result_reg, rc_required?)
            b4 = Builder.emit_ret(b3, ret_reg)

            plan =
              Builder.to_function_plan(b4)
              |> EpilogueRelease.run()
              |> Optimize.run()
              |> EpilogueRelease.run()
              |> NativeReturn.annotate(decl)

            case Verify.run(plan) do
              :ok ->
                case verify_lambda_plans(Map.get(plan, :lambdas, [])) do
                  :ok -> {:ok, plan}
                  {:error, reason, meta} -> {:error, {:verify, reason, meta}}
                end

              {:error, reason, meta} ->
                {:error, {:verify, reason, meta}}
            end

          :unsupported ->
            record_plan_unsupported(module_name, name, expr)
        end

      :unsupported ->
        record_plan_unsupported(module_name, name, expr)
    end
  end

  defp record_plan_unsupported(module_name, name, expr) do
    cache = Process.get(:elmc_plan_unsupported_reasons, %{})

    reason =
      %{
        op: Map.get(expr, :op),
        target: Map.get(expr, :target) || Map.get(expr, :name),
        kind: Map.get(expr, :kind)
      }

    Process.put(:elmc_plan_unsupported_reasons, Map.put_new(cache, {module_name, name}, reason))
    :unsupported
  end

  @spec seed_param_types(Context.t(), Types.decl()) :: Context.t()

  defp seed_param_types(%Context{} = ctx, decl) when is_map(decl) do
    type = Map.get(decl, :type)

    with type when is_binary(type) <- type,
         arg_types when is_list(arg_types) <- Elmc.Backend.CCodegen.TypeParsing.function_arg_types(type) do
      types =
        ctx.params
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {param, idx}, acc ->
          case Enum.at(arg_types, idx) do
            t when is_binary(t) -> Map.put(acc, param, Elmc.Backend.CCodegen.Host.normalize_type_name(t))
            _ -> acc
          end
        end)

      %{ctx | local_types: Map.merge(ctx.local_types, types)}
    else
      _ -> ctx
    end
  end

  @spec seed_inferred_param_fields(Context.t(), Types.decl()) :: Context.t()

  defp seed_inferred_param_fields(%Context{} = ctx, decl) when is_map(decl) do
    case ParamFieldInference.infer(decl) do
      fields when map_size(fields) > 0 -> %{ctx | inferred_param_fields: fields}
      _ -> ctx
    end
  end

  @spec finalize_result(Builder.t(), Types.reg() | :fn_out | term(), boolean() | term()) ::
          {Builder.t(), Types.reg() | :fn_out | term()}

  defp finalize_result(b, :fn_out, true), do: {b, :fn_out}
  defp finalize_result(b, :fn_out, false), do: {b, :fn_out}

  defp finalize_result(b, result_reg, true) when is_integer(result_reg) do
    {Builder.emit_publish_fn_out(b, result_reg), :fn_out}
  end

  defp finalize_result(b, result_reg, false) when is_integer(result_reg), do: {b, result_reg}
  defp finalize_result(b, result_reg, _), do: {b, result_reg}

  @spec preload_params(Builder.t(), [String.t()]) :: Builder.t()

  defp preload_params(b, args) do
    Enum.reduce(Enum.with_index(args), b, fn {name, idx}, b_acc ->
      {_reg, b1} = Builder.get_or_load_param(b_acc, idx, name)
      b1
    end)
  end

  @spec verify_lambda_plans([Types.function_plan() | map()]) ::
          :ok | {:error, term(), term()}

  defp verify_lambda_plans(lambdas) when is_list(lambdas) do
    Enum.reduce_while(lambdas, :ok, fn lam, :ok ->
      case Verify.run(lam |> EpilogueRelease.run() |> Optimize.run() |> EpilogueRelease.run()) do
        :ok -> {:cont, :ok}
        {:error, reason, meta} -> {:halt, {:error, reason, meta}}
      end
    end)
  end

  # Native Int/Bool bodies lowered to value-return C ABI skip *out tails; thin user
  # delegates (for example nthEmptyIndex -> nthEmptyIndexHelp) still tail into out.
  # Non-RC boxed returns (for example Pebble.Ui.window) may tail with `return …`.
  @spec function_tail_compile?(Types.decl(), String.t(), Types.decl_map(), boolean()) :: boolean()

  defp function_tail_compile?(decl, module_name, decl_map, rc_required?) do
    cond do
      rc_required? ->
        boxed_tail_compile?(decl, module_name, decl_map)

      boxed_tail_compile?(decl, module_name, decl_map) ->
        true

      literal_boxed_tail?(decl) ->
        true

      true ->
        false
    end
  end

  @spec literal_boxed_tail?(map() | term()) :: boolean()

  defp literal_boxed_tail?(%{expr: %{op: :int_literal}}), do: true
  defp literal_boxed_tail?(%{expr: %{op: :call_runtime, args: %{builtin: :new_int}}}), do: true
  defp literal_boxed_tail?(_), do: false

  @spec boxed_tail_compile?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp boxed_tail_compile?(decl, module_name, decl_map) do
    case Host.function_return_type(Map.get(decl, :type)) do
      ret when ret in ["Int", "Bool"] ->
        ThinDelegate.thin_delegate?(decl, module_name, decl_map)

      _ ->
        true
    end
  end
end
