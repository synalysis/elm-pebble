defmodule Elmc.Backend.Wasm.Lower.Frame do
  @moduledoc false

  alias Elmc.Backend.Wasm.Slots
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @rc_success 0

  @spec init_rc(Slots.t()) :: iodata()
  def init_rc(slots) do
    WasmTypes.line(
      WasmTypes.sexpr("local.set", [
        slots.rc_local,
        " ",
        WasmTypes.sexpr("i32.const", [@rc_success])
      ])
    )
  end

  @spec epilogue_release(Slots.t()) :: iodata()
  def epilogue_release(%{owned_count: 0}), do: []

  def epilogue_release(slots) do
    import_name =
      "runtime.release_unless_reachable_from_roots"
      |> WasmTypes.import_ident()

    roots_scratch = Slots.int_array_scratch_offset()
    root_count = 1 + slots.params
    fn_out = slots.fn_out_local

    store_roots = emit_epilogue_roots(slots, roots_scratch, fn_out)

    if slots.owned_count > 0 do
      releases =
        Enum.flat_map(0..(slots.owned_count - 1)//1, fn idx ->
          owned = Slots.owned_local(slots, idx)

          [
            WasmTypes.line(
              WasmTypes.sexpr("if", [
                WasmTypes.sexpr("i32.ne", [
                  " ",
                  WasmTypes.sexpr("local.get", [owned]),
                  " ",
                  WasmTypes.sexpr("i32.const", [0])
                ]),
                " (then ",
                WasmTypes.sexpr("drop", [
                  " ",
                  WasmTypes.sexpr("call", [
                    import_name,
                    " ",
                    WasmTypes.sexpr("local.get", [owned]),
                    " ",
                    WasmTypes.sexpr("i32.const", [roots_scratch]),
                    " ",
                    WasmTypes.sexpr("i32.const", [root_count])
                  ])
                ]),
                ")"
              ])
            )
          ]
        end)
        |> Enum.reverse()

      store_roots ++ releases
    else
      store_roots
    end
  end

  defp emit_epilogue_roots(slots, scratch, fn_out) do
    fn_out_store =
      WasmTypes.line(
        WasmTypes.sexpr("i32.store", [
          " offset=#{scratch} ",
          WasmTypes.sexpr("i32.const", [0]),
          " ",
          WasmTypes.sexpr("local.get", [fn_out])
        ])
      )

    param_stores =
      Enum.map(0..(slots.params - 1)//1, fn index ->
        offset = scratch + 4 * (index + 1)

        WasmTypes.line(
          WasmTypes.sexpr("i32.store", [
            " offset=#{offset} ",
            WasmTypes.sexpr("i32.const", [0]),
            " ",
            WasmTypes.sexpr("local.get", ["$param#{index}"])
          ])
        )
      end)

    [fn_out_store | param_stores]
  end

  @spec box_native_scalar_return(Elmc.Backend.Plan.Types.FunctionPlan.t(), Slots.t()) :: iodata()
  def box_native_scalar_return(%{native_scalar_return: kind}, slots) when kind in [:native_int, :native_bool] do
    import_sym =
      (case kind do
         :native_int -> Elmc.Backend.Wasm.RuntimeImports.import_name(:new_int)
         :native_bool -> Elmc.Backend.Wasm.RuntimeImports.import_name(:new_bool)
       end)
      |> WasmTypes.import_ident()

    mem_offset = slots.fn_out_mem

    [
      WasmTypes.line(
        WasmTypes.sexpr("call", [
          import_sym,
          " ",
          WasmTypes.sexpr("i32.const", [mem_offset]),
          " ",
          WasmTypes.sexpr("local.get", [slots.fn_out_local])
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
  end

  def box_native_scalar_return(_plan, _slots), do: []

  @spec return_rc(Slots.t()) :: iodata()
  def return_rc(slots) do
    WasmTypes.line(
      WasmTypes.sexpr("return", [
        " ",
        WasmTypes.sexpr("local.get", [slots.rc_local]),
        " ",
        WasmTypes.sexpr("local.get", [slots.fn_out_local])
      ])
    )
  end

  @spec catch_begin_label(non_neg_integer()) :: String.t()
  def catch_begin_label(id), do: "$catch_end_#{id}"

  @spec wrap_catch(boolean(), iodata(), non_neg_integer()) :: iodata()
  def wrap_catch(false, body, _id), do: body

  def wrap_catch(true, body, id) do
    label = catch_begin_label(id)

    [
      WasmTypes.line(WasmTypes.sexpr_open("block", [" ", label])),
      WasmTypes.indent(body, 1),
      "\n",
      WasmTypes.line(") ;; end catch block")
    ]
  end
end
