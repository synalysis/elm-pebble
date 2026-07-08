defmodule Elmc.Backend.Plan.Lower.Intrinsics do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context, EpilogueRelease, Verify}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec try_lower(map(), String.t(), map(), keyword()) ::
          {:ok, FunctionPlan.t()} | :not_intrinsic | {:error, term()}
  def try_lower(decl, module_name, decl_map, opts) do
    case decl do
      %{name: "toInt", args: [param_name], expr: %{op: :case}} ->
        lower_color_to_int_identity(decl, module_name, param_name, decl_map, opts)

      %{expr: %{op: :qualified_call, target: target, args: []}} ->
        if batch_kernel_target?(target) do
          lower_batch_kernel_alias(decl, module_name, decl_map, opts)
        else
          :not_intrinsic
        end

      _ ->
        :not_intrinsic
    end
  end

  defp lower_color_to_int_identity(decl, module_name, param_name, decl_map, opts) do
    if module_name != "Pebble.Ui.Color" do
      :not_intrinsic
    else
      lower_param_identity(decl, module_name, param_name, decl_map, opts)
    end
  end

  defp lower_batch_kernel_alias(decl, module_name, decl_map, opts) do
    name = Map.get(decl, :name, "batch")
    rc_required? = Keyword.get(opts, :rc_required, false)

    ctx =
      Context.new(
        module: module_name,
        function_name: name,
        decl_map: decl_map,
        params: Map.get(decl, :args, []),
        rc_required: rc_required?,
        fallible: true,
        function_tail: false
      )

    b =
      Builder.new(module_name, name,
        args: Map.get(decl, :args, []),
        rc_required: rc_required?,
        fallible: true
      )

    with {:ok, result_reg, b1} <- Expr.compile(%{op: :int_literal, value: 0}, ctx, b),
         {b2, ret_reg} <- finalize_result(b1, result_reg, rc_required?),
         b3 <- Builder.emit_ret(b2, ret_reg),
         plan <- Builder.to_function_plan(b3) |> EpilogueRelease.run(),
         :ok <- Verify.run(plan) do
      {:ok, plan}
    else
      {:error, _, _} = err -> err
    end
  end

  defp lower_param_identity(decl, module_name, param_name, _decl_map, opts) do
    name = Map.get(decl, :name, "anon")
    rc_required? = Keyword.get(opts, :rc_required, false)

    b =
      Builder.new(module_name, name,
        args: [param_name],
        rc_required: rc_required?,
        fallible: true
      )

    with {reg, b1} <- Builder.get_or_load_param(b, 0, param_name),
         {b2, ret_reg} <- finalize_result(b1, reg, rc_required?),
         b3 <- Builder.emit_ret(b2, ret_reg),
         plan <- Builder.to_function_plan(b3) |> EpilogueRelease.run(),
         :ok <- Verify.run(plan) do
      {:ok, plan}
    else
      {:error, _, _} = err -> err
    end
  end

  defp finalize_result(b, :fn_out, true), do: {b, :fn_out}
  defp finalize_result(b, :fn_out, false), do: {b, :fn_out}

  defp finalize_result(b, result_reg, true) when is_integer(result_reg) do
    {Builder.emit_publish_fn_out(b, result_reg), :fn_out}
  end

  defp finalize_result(b, result_reg, false) when is_integer(result_reg), do: {b, result_reg}
  defp finalize_result(b, result_reg, _), do: {b, result_reg}

  defp batch_kernel_target?(target) when is_binary(target) do
    String.ends_with?(target, ".batch") or target == "batch"
  end

  defp batch_kernel_target?(_), do: false
end
