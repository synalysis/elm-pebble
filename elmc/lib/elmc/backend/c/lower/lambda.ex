defmodule Elmc.Backend.C.Lower.Lambda do
  @moduledoc false

  alias Elmc.Backend.C.Lower.{Frame, Function}
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @emitted_key :elmc_plan_closure_emitted

  @spec ensure_emitted!(FunctionPlan.t()) :: :ok
  def ensure_emitted!(%FunctionPlan{} = parent) do
    (parent.lambdas || [])
    |> Enum.each(&ensure_emitted!/1)

    (parent.lambdas || [])
    |> Enum.with_index()
    |> Enum.each(fn {lambda, idx} ->
      ensure_one!(parent, lambda, idx)
    end)

    :ok
  end

  @spec closure_fn_name(FunctionPlan.t(), non_neg_integer()) :: String.t()
  def closure_fn_name(%FunctionPlan{} = parent, idx) when is_integer(idx) do
    "#{Util.module_fn_name(parent.module, parent.name)}_closure_#{idx}"
  end

  defp ensure_one!(parent, %FunctionPlan{} = _lambda, idx) do
    key = {parent.module, parent.name, idx}
    emitted = Process.get(@emitted_key, MapSet.new())

    if MapSet.member?(emitted, key) do
      :ok
    else
      defn = emit_closure_def(parent, idx)
      Process.put(:elmc_lambdas, [defn | Process.get(:elmc_lambdas, [])])
      Process.put(@emitted_key, MapSet.put(emitted, key))
      :ok
    end
  end

  defp emit_closure_def(%FunctionPlan{} = parent, idx) do
    lambda = Enum.at(parent.lambdas, idx)
    closure_name = closure_fn_name(parent, idx)
    capture_count = capture_count(lambda)
    {slots, slot_count} =
      Function.prepared_owned_slots(lambda, closure_mode: %{capture_count: capture_count})

    slot_indices = if slot_count > 0, do: Enum.to_list(0..(slot_count - 1)), else: []

    owned = Frame.owned_declaration(lambda, slots)
    epilogue = Frame.epilogue_release(slot_indices, slot_count)
    letrec_decls = Function.letrec_decl_lines(lambda.letrec_refs || [])
    letrec_free = Function.letrec_free_lines(lambda.letrec_refs || [])

    core =
      Function.emit_core(lambda,
        shell: false,
        closure_mode: %{capture_count: capture_count}
      )

    body =
      Frame.wrap_catch(lambda.rc_required and lambda.fallible, core)
      |> String.trim()

  void_casts =
      ["args", "argc", "captures", "capture_count"]
      |> Enum.reject(&closure_param_used?(&1, body))
      |> Enum.map_join("\n  ", &"(void)#{&1};")

    if lambda.rc_required do
      """
      static RC #{closure_name}(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        #{void_casts}
        RC Rc = RC_SUCCESS;
        #{Enum.join(letrec_decls, "\n  ")}
        #{owned}
        #{body}
        #{Enum.join(letrec_free, "\n  ")}
        #{epilogue}
        return Rc;
      }
      """
      |> String.trim()
    else
      """
      static ElmcValue *#{closure_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        #{void_casts}
        #{Enum.join(letrec_decls, "\n  ")}
        #{owned}
        #{body}
        #{Enum.join(letrec_free, "\n  ")}
        #{epilogue}
      }
      """
      |> String.trim()
    end
  end

  defp closure_param_used?(param, body) when is_binary(param) and is_binary(body) do
    Regex.match?(~r/\b#{Regex.escape(param)}\b/, body)
  end

  @spec capture_count(FunctionPlan.t()) :: non_neg_integer()
  def capture_count(%FunctionPlan{params: params, lambda_arg_count: arg_count})
      when is_integer(arg_count) and arg_count >= 0 do
    max(length(params) - arg_count, 0)
  end

  def capture_count(%FunctionPlan{params: params}), do: length(params)
end
