defmodule Elmc.Backend.C.Lower.Lambda do
  @moduledoc false

  alias Elmc.Backend.C.Lower.{Frame, Function}
  alias Elmc.Backend.CCodegen.{RecordCompile, Util}
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

  @spec ensure_one!(FunctionPlan.t(), FunctionPlan.t(), non_neg_integer()) :: :ok

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

  @spec emit_closure_def(FunctionPlan.t(), non_neg_integer()) :: String.t()

  defp emit_closure_def(%FunctionPlan{} = parent, idx) do
    lambda = Enum.at(parent.lambdas, idx)
    closure_name = closure_fn_name(parent, idx)
    capture_count = capture_count(lambda)
    parent_borrowed = Process.get(:elmc_borrowed_field_refs, MapSet.new())
    RecordCompile.reset_borrowed_field_refs()

    {core, slots} =
      Function.emit_core_with_slots(lambda,
        shell: false,
        closure_mode: %{capture_count: capture_count}
      )

    slot_count = Function.owned_slot_count(slots)
    slot_indices = if slot_count > 0, do: Enum.to_list(0..(slot_count - 1)), else: []

    owned = Frame.owned_declaration(lambda, slots)

    epilogue =
      [
        RecordCompile.borrowed_owned_refs_null_stmt(),
        Frame.epilogue_release(slot_indices, slot_count)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    Process.put(:elmc_borrowed_field_refs, parent_borrowed)
    capture_indices = Map.get(lambda, :letrec_capture_indices) || %{}

    all_ref_names =
      (lambda.letrec_refs ++ Function.forward_ref_names_in_plan(lambda))
      |> Enum.uniq()

    {captured_refs, local_refs} =
      Enum.split_with(all_ref_names, &Map.has_key?(capture_indices, &1))

    letrec_decls =
      Enum.map(captured_refs, fn ref ->
        idx = Map.fetch!(capture_indices, ref)

        "ElmcForwardRef *#{ref} = (capture_count > #{idx} && captures[#{idx}] && captures[#{idx}]->tag == ELMC_TAG_FORWARD_REF && captures[#{idx}]->payload) ? *((ElmcForwardRef **)captures[#{idx}]->payload) : NULL;"
      end) ++ Function.letrec_decl_lines(local_refs)

    # Parent owns captured forward refs; only free ones this closure allocated.
    letrec_free = Function.letrec_free_lines(local_refs)

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

  @spec closure_param_used?(String.t(), String.t()) :: boolean()

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
