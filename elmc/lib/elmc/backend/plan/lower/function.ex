defmodule Elmc.Backend.Plan.Lower.Function do
  @moduledoc """
  Lower a whole function declaration expr to `%FunctionPlan{}`.
  """

  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.Plan.Fusion
  alias Elmc.Backend.Plan.{Builder, Context, EpilogueRelease, Optimize, ThinDelegate, Verify}
  alias Elmc.Backend.Plan.Lower.{Expr, Intrinsics}
  alias Elmc.Backend.Plan.Types

  @spec lower(Types.function_decl(), String.t(), Types.function_decl_map(), keyword()) ::
          Types.lower_result()
  def lower(decl, module_name, decl_map, opts \\ []) do
    try do
      do_lower(decl, module_name, decl_map, opts)
    rescue
      FunctionClauseError -> :unsupported
    end
  end

  defp do_lower(decl, module_name, decl_map, opts) do
    case Fusion.try_plan(module_name, decl, decl_map, opts) do
      {:ok, plan} ->
        {:ok, register_fusion_native_cache(plan, module_name)}

      :error ->
        case Intrinsics.try_lower(decl, module_name, decl_map, opts) do
          {:ok, plan} ->
            {:ok, plan}

          :not_intrinsic ->
            lower_expr_body(decl, module_name, decl_map, opts)

          {:error, _, _} = err ->
            err
        end
    end
  end

  defp register_fusion_native_cache(%{fusion_c: c, native_scalar_return: kind} = plan, module_name)
       when is_binary(c) and kind in [:native_int, :native_bool] do
    NativeReturn.cache_scalar_return(module_name, plan.name, kind)

    if Map.get(plan, :native_scalar_value_return) == true do
      NativeReturn.cache_scalar_value_return(module_name, plan.name)
    end

    plan
  end

  defp register_fusion_native_cache(plan, _module_name), do: plan

  defp lower_expr_body(decl, module_name, decl_map, opts) do
    expr = Map.get(decl, :expr) || %{op: :int_literal, value: 0}
    args = Map.get(decl, :args, [])
    name = Map.get(decl, :name, "anon")
    rc_required? = Keyword.get(opts, :rc_required, RcRequired.rc_required?(module_name, name))

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

    b = Builder.new(module_name, name,
      args: args,
      rc_required: rc_required?,
      fallible: true
    )

    b_entry = preload_params(b, args)

    case Expr.compile(expr, ctx, b_entry) do
      {:ok, result_reg, b1} ->
        {b2, ret_reg} = finalize_result(b1, result_reg, rc_required?)
        b4 = Builder.emit_ret(b2, ret_reg)

        plan =
          Builder.to_function_plan(b4)
          |> EpilogueRelease.run()
          |> Optimize.run()
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
        :unsupported
    end
  end

  defp finalize_result(b, :fn_out, true), do: {b, :fn_out}
  defp finalize_result(b, :fn_out, false), do: {b, :fn_out}

  defp finalize_result(b, result_reg, true) when is_integer(result_reg) do
    {Builder.emit_publish_fn_out(b, result_reg), :fn_out}
  end

  defp finalize_result(b, result_reg, false) when is_integer(result_reg), do: {b, result_reg}
  defp finalize_result(b, result_reg, _), do: {b, result_reg}

  defp preload_params(b, args) do
    Enum.reduce(Enum.with_index(args), b, fn {name, idx}, b_acc ->
      {_reg, b1} = Builder.get_or_load_param(b_acc, idx, name)
      b1
    end)
  end

  defp verify_lambda_plans(lambdas) when is_list(lambdas) do
    Enum.reduce_while(lambdas, :ok, fn lam, :ok ->
      case Verify.run(EpilogueRelease.run(lam) |> Optimize.run()) do
        :ok -> {:cont, :ok}
        {:error, reason, meta} -> {:halt, {:error, reason, meta}}
      end
    end)
  end

  # Native Int/Bool bodies lowered to value-return C ABI skip *out tails; thin user
  # delegates (for example nthEmptyIndex -> nthEmptyIndexHelp) still tail into out.
  # Non-RC boxed returns (for example Pebble.Ui.window) may tail with `return …`.
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

  defp literal_boxed_tail?(%{expr: %{op: :int_literal}}), do: true
  defp literal_boxed_tail?(%{expr: %{op: :call_runtime, args: %{builtin: :new_int}}}), do: true
  defp literal_boxed_tail?(_), do: false

  defp boxed_tail_compile?(decl, module_name, decl_map) do
    case Host.function_return_type(Map.get(decl, :type)) do
      ret when ret in ["Int", "Bool"] ->
        ThinDelegate.thin_delegate?(decl, module_name, decl_map)

      _ ->
        true
    end
  end
end
