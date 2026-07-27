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
  def lower_stub(%{module: "Float", name: "Extra.interpolateFrom", arity: arity} = entry)
      when arity >= 3 do
    params = Enum.map(0..(arity - 1), &"param#{&1}")

    %{
      export_name: WasmTypes.fn_ident(entry.module, entry.name),
      module: entry.module,
      name: entry.name,
      params: params,
      rc_required: true,
      body: interpolate_from_body(),
      imports: MapSet.new(["runtime.float_interpolate_from"]),
      import_arities: %{"runtime.float_interpolate_from" => 3}
    }
  end

  # elm-explorations/linear-algebra Vector2/Vector3/Vector4/Matrix4 kernels.
  # These are pure numeric ops (no Elm plan body), so every call site becomes
  # a missing_callee stub; route them all through one host implementation per
  # kernel name (runtime.mjs_<name>) instead of RC_ERR_UNIMPLEMENTED.
  def lower_stub(%{module: "Elm.Kernel.MJS", name: name, arity: arity} = entry) do
    params =
      if arity == 0 do
        []
      else
        Enum.map(0..(arity - 1), &"param#{&1}")
      end

    import_name = "runtime.mjs_#{name}"

    %{
      export_name: WasmTypes.fn_ident(entry.module, entry.name),
      module: entry.module,
      name: entry.name,
      params: params,
      rc_required: true,
      body: host_value_stub_body(params, import_name),
      imports: MapSet.new([import_name]),
      import_arities: %{import_name => arity}
    }
  end

  # elm-explorations/webgl kernels — host builds entity records and VDOM custom
  # canvas widgets (see elmc-wasm-runtime/host/webgl_runtime.js).
  def lower_stub(%{module: "Elm.Kernel.WebGL", name: "entity", arity: arity} = entry)
      when arity >= 5 do
    params = Enum.map(0..(arity - 1), &"param#{&1}")
    import_name = "runtime.webgl_entity"

    %{
      export_name: WasmTypes.fn_ident(entry.module, entry.name),
      module: entry.module,
      name: entry.name,
      params: params,
      rc_required: true,
      body: host_value_stub_body(Enum.take(params, 5), import_name),
      imports: MapSet.new([import_name]),
      import_arities: %{import_name => 5}
    }
  end

  def lower_stub(%{module: "Elm.Kernel.WebGL", name: "toHtml", arity: arity} = entry)
      when arity >= 3 do
    params = Enum.map(0..(arity - 1), &"param#{&1}")
    import_name = "runtime.webgl_to_html"

    %{
      export_name: WasmTypes.fn_ident(entry.module, entry.name),
      module: entry.module,
      name: entry.name,
      params: params,
      rc_required: true,
      body: host_value_stub_body(Enum.take(params, 3), import_name),
      imports: MapSet.new([import_name]),
      import_arities: %{import_name => 3}
    }
  end

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

  defp interpolate_from_body do
    """
    (local $out i32)
    local.get $param0
    local.get $param1
    local.get $param2
    call $runtime_float_interpolate_from
    local.set $out
    i32.const 0
    local.get $out
    """
  end

  defp stub_body do
    """
    i32.const #{@rc_err_unimplemented}
    i32.const 0
    """
  end

  defp host_value_stub_body(params, import_name) do
    loads = Enum.map_join(params, "\n", &"local.get $#{&1}")

    """
    (local $out i32)
    #{loads}
    call #{WasmTypes.import_ident(import_name)}
    local.set $out
    i32.const 0
    local.get $out
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
