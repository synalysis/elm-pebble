defmodule Elmc.Backend.Wasm.Lower.FusionFunction do
  @moduledoc false

  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Backend.Wasm.Lower.Frame
  alias Elmc.Backend.Wasm.RuntimeImports
  alias Elmc.Backend.Wasm.Slots
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @wasm_fusion_kinds [:list_indexed_replace]
  @rc_success 0

  @spec emittable?(FunctionPlan.t()) :: boolean()
  def emittable?(%FunctionPlan{fusion_kind: kind}) when kind in @wasm_fusion_kinds, do: true
  def emittable?(_), do: false

  @spec lower(FunctionPlan.t()) :: Elmc.Backend.Wasm.Lower.Function.function_unit()
  def lower(%FunctionPlan{fusion_kind: :list_indexed_replace} = plan) do
    lower_list_indexed_replace(plan)
  end

  defp lower_list_indexed_replace(%FunctionPlan{} = plan) do
    slots = Slots.build(plan)
    import_name = RuntimeImports.import_name(:list_replace_nth_int)
    import_sym = WasmTypes.import_ident(import_name)
    mem_offset = slots.fn_out_mem

    call =
      WasmTypes.sexpr("call", [
        import_sym,
        " ",
        WasmTypes.sexpr("i32.const", [mem_offset]),
        " ",
        WasmTypes.sexpr("local.get", ["$param2"]),
        " ",
        WasmTypes.sexpr("local.get", ["$param0"]),
        " ",
        WasmTypes.sexpr("local.get", ["$param1"])
      ])

    body_core = [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          slots.rc_local,
          " ",
          call
        ])
      ),
      WasmTypes.line(
        WasmTypes.sexpr("br_if", [
          " ",
          Frame.catch_begin_label(0),
          " ",
          WasmTypes.sexpr("i32.ne", [
            " ",
            WasmTypes.sexpr("local.get", [slots.rc_local]),
            " ",
            WasmTypes.sexpr("i32.const", [@rc_success])
          ])
        ])
      ),
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          slots.fn_out_local,
          " ",
          WasmTypes.i32_load_offset(mem_offset)
        ])
      )
    ]

    body =
      [
        Slots.local_decls(slots),
        Frame.init_rc(slots),
        Frame.wrap_catch(true, body_core, 0),
        Frame.epilogue_release(slots),
        Frame.return_rc(slots)
      ]
      |> IO.iodata_to_binary()

    %{
      export_name: WasmTypes.fn_ident(plan.module, plan.name),
      module: plan.module,
      name: plan.name,
      params: param_names(plan),
      rc_required: plan.rc_required,
      body: body,
      imports: MapSet.new([import_name]),
      import_arities: %{import_name => 4}
    }
  end

  defp param_names(%FunctionPlan{params: params}) do
    Enum.map(params || [], fn
      name when is_binary(name) -> name
      %{name: name} -> name
      other -> inspect(other)
    end)
  end
end
