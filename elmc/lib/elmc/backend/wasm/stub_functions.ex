defmodule Elmc.Backend.Wasm.StubFunctions do
  @moduledoc false

  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @rc_err_unimplemented 100

  @type callee :: {String.t(), String.t()}
  @type stub_entry :: %{
          module: String.t(),
          name: String.t(),
          export: String.t(),
          arity: non_neg_integer(),
          kind: :kernel_stub | :missing_callee_stub
        }

  @spec missing_callees([FunctionPlan.t()]) :: [stub_entry()]
  def missing_callees(plans) when is_list(plans) do
    emitted =
      plans
      |> flatten_plans()
      |> MapSet.new(fn %FunctionPlan{module: mod, name: name} -> {mod, name} end)

    plans
    |> callee_use_map()
    |> Enum.reject(fn {{mod, name}, _arity} -> MapSet.member?(emitted, {mod, name}) end)
    |> Enum.map(fn {{mod, name}, arity} ->
      %{
        module: mod,
        name: name,
        export: WasmTypes.fn_ident(mod, name) |> strip_dollar(),
        arity: arity,
        kind: stub_kind_internal(mod)
      }
    end)
    |> Enum.sort_by(&{&1.module, &1.name})
  end

  @spec lower_stub(stub_entry()) :: map()
  def lower_stub(%{module: mod, name: name, arity: arity}) do
    params =
      if arity == 0 do
        []
      else
        Enum.map(0..(arity - 1), &"param#{&1}")
      end

    %{
      export_name: WasmTypes.fn_ident(mod, name),
      module: mod,
      name: name,
      params: params,
      rc_required: true,
      body: stub_body(),
      imports: MapSet.new(),
      import_arities: %{}
    }
  end

  defp stub_body do
    """
    i32.const #{@rc_err_unimplemented}
    i32.const 0
    """
  end

  defp callee_use_map(plans) do
    plans
    |> flatten_plans()
    |> Enum.reduce(%{}, fn plan, acc ->
      plan.blocks
      |> Enum.concat(Enum.flat_map(Map.get(plan, :lambdas, []), & &1.blocks))
      |> Enum.reduce(acc, fn %Block{instrs: instrs}, acc_block ->
        Enum.reduce(instrs, acc_block, fn
          %{op: :call_fn, args: %{module: mod, name: name, args: args}}, acc_instr ->
            arity = args |> List.wrap() |> length()
            Map.update(acc_instr, {mod, name}, arity, &Kernel.max(&1, arity))

          _, acc_instr ->
            acc_instr
        end)
      end)
    end)
  end

  defp flatten_plans(plans) do
    Enum.flat_map(plans, fn plan ->
      [plan | flatten_plans(Map.get(plan, :lambdas, []))]
    end)
  end

  @spec stub_kind(String.t()) :: :kernel_stub | :missing_callee_stub
  def stub_kind("Elm.Kernel." <> _), do: :kernel_stub
  def stub_kind("Elm.Kernel"), do: :kernel_stub
  def stub_kind(_), do: :missing_callee_stub

  defp stub_kind_internal(module), do: stub_kind(module)

  defp strip_dollar("$" <> rest), do: rest
  defp strip_dollar(other), do: other
end
