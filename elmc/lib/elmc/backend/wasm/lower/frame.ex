defmodule Elmc.Backend.Wasm.Lower.Frame do
  @moduledoc false

  alias Elmc.Backend.Plan.Types.FunctionPlan
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
  def epilogue_release(slots), do: lifo_owned_release(slots)

  # C-shaped LIFO: newest owned slot first. Consumed transfers already
  # nulled their shadows, so `$fn_out` is not in `owned[]`.
  @spec lifo_owned_release(Slots.t()) :: iodata()
  def lifo_owned_release(%{owned_count: n}) when not is_integer(n) or n <= 0, do: []

  def lifo_owned_release(slots) do
    release = WasmTypes.import_ident("runtime.release")
    fn_out = slots.fn_out_local

    Enum.flat_map((slots.owned_count - 1)..0//-1, fn idx ->
      owned = Slots.owned_local(slots, idx)

      cond_wat =
        WasmTypes.sexpr("i32.and", [
          " ",
          WasmTypes.sexpr("i32.ne", [
            " ",
            WasmTypes.sexpr("local.get", [owned]),
            " ",
            WasmTypes.sexpr("i32.const", [0])
          ]),
          " ",
          WasmTypes.sexpr("i32.ne", [
            " ",
            WasmTypes.sexpr("local.get", [owned]),
            " ",
            WasmTypes.sexpr("local.get", [fn_out])
          ])
        ])

      [
        WasmTypes.line(
          WasmTypes.sexpr("if", [
            cond_wat,
            " (then ",
            WasmTypes.sexpr("drop", [
              " ",
              WasmTypes.sexpr("call", [
                release,
                " ",
                WasmTypes.sexpr("local.get", [owned])
              ])
            ]),
            " ",
            WasmTypes.sexpr("local.set", [
              owned,
              " ",
              WasmTypes.sexpr("i32.const", [0])
            ]),
            ")"
          ])
        )
      ]
    end)
  end

  @spec box_native_scalar_return(Elmc.Backend.Plan.Types.FunctionPlan.t(), Slots.t()) :: iodata()
  def box_native_scalar_return(%{native_scalar_return: :native_int} = plan, slots) do
    # `publish_fn_out` may already have boxed via runtime.new_int; only box here
    # when $fn_out still holds a raw native i32 (compare / const / arith / etc.).
    maybe_box_fn_out_tail(plan, slots, :native_int)
  end

  def box_native_scalar_return(%{native_scalar_return: :native_bool} = plan, slots) do
    maybe_box_fn_out_tail(plan, slots, :native_bool)
  end

  def box_native_scalar_return(%{native_scalar_return: :native_float} = plan, slots) do
    maybe_box_fn_out_tail(plan, slots, :native_float)
  end

  def box_native_scalar_return(_plan, _slots), do: []

  defp maybe_box_fn_out_tail(plan, slots, kind) do
    if plan_tail_boxes_fn_out?(plan) do
      []
    else
      box_native_scalar_return_impl(kind, slots)
    end
  end

  defp plan_tail_boxes_fn_out?(%FunctionPlan{} = plan) do
    native? = Elmc.Backend.Plan.ScalarKind.native_return?(Map.get(plan, :native_scalar_return))

    # Skip epilogue boxing only when the body already placed a boxed handle in
    # $fn_out. `Instr.publish_fn_out/3` boxes on `{:ret, reg}` / `:publish` when
    # native_scalar_return is set. `{:ret, :fn_out}` means a prior instr wrote
    # $fn_out and may still hold a raw i32 (constant-folded probeNot).
    case last_fn_out_write(plan.blocks) do
      {:call_runtime, builtin} when builtin in [:new_int, :new_bool, :new_float] -> true
      {:call_runtime, _} -> true
      {:publish, _} -> native?
      {:ret, reg} when is_integer(reg) -> native?
      {:ret, :fn_out} -> fn_out_already_boxed_in_instrs?(plan.blocks)
      _ -> false
    end
  end

  defp last_fn_out_write(blocks) do
    from_instrs =
      blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.reverse()
      |> Enum.find_value(fn
        %{op: :call_runtime, dest: dest, args: %{builtin: builtin}}
        when dest in [:fn_out, :branch_out] and is_atom(builtin) ->
          {:call_runtime, builtin}

        %{op: :publish, dest: dest, args: %{source: reg}}
        when dest in [:fn_out, :branch_out] and is_integer(reg) ->
          {:publish, reg}

        _ ->
          nil
      end)

    from_instrs ||
      blocks
      |> Enum.reverse()
      |> Enum.find_value(fn
        %{terminator: {:ret, :fn_out}} -> {:ret, :fn_out}
        %{terminator: {:ret, reg}} when is_integer(reg) -> {:ret, reg}
        _ -> nil
      end)
  end

  defp fn_out_already_boxed_in_instrs?(blocks) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.any?(fn
      %{op: :call_runtime, dest: dest, args: %{builtin: builtin}}
      when dest in [:fn_out, :branch_out] and builtin in [:new_int, :new_bool, :new_float] ->
        true

      _ ->
        false
    end)
  end

  defp box_native_scalar_return_impl(kind, slots) do
    import_sym =
      (case kind do
         :native_int -> Elmc.Backend.Wasm.RuntimeImports.import_name(:new_int)
         :native_bool -> Elmc.Backend.Wasm.RuntimeImports.import_name(:new_bool)
         :native_float -> Elmc.Backend.Wasm.RuntimeImports.import_name(:new_float)
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
