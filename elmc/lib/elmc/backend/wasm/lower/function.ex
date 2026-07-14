defmodule Elmc.Backend.Wasm.Lower.Function do
  @moduledoc false

  alias Elmc.Backend.Bytecode.FnTable
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.Wasm.{ClosureRegistry, ImportCollect}
  alias Elmc.Backend.Wasm.Lower.{Frame, FusionFunction, Instr}
  alias Elmc.Backend.Wasm.Slots
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @plan_switch_done "$plan_switch_done"
  @plan_loop "$plan_loop"

  @type function_unit :: %{
          export_name: String.t(),
          module: String.t(),
          name: String.t(),
          params: [String.t()],
          rc_required: boolean(),
          body: iodata(),
          imports: MapSet.t(String.t()),
          import_arities: %{String.t() => non_neg_integer()}
        }

  @spec lower_closure(FunctionPlan.t(), FunctionPlan.t(), non_neg_integer()) :: function_unit()
  def lower_closure(%FunctionPlan{} = parent, %FunctionPlan{} = lambda, idx) when is_integer(idx) do
    lambda = annotate_lambda_return(lambda)

    lower_plan(lambda,
      export_name: ClosureRegistry.export_name(parent, idx),
      name: "#{parent.name}_closure_#{idx}"
    )
  end

  defp annotate_lambda_return(%FunctionPlan{} = lambda) do
    lambda
    |> NativeReturn.annotate(%{type: "Int"})
    |> then(fn plan ->
      if Map.get(plan, :native_scalar_return) do
        plan
      else
        NativeReturn.annotate(plan, %{type: "Bool"})
      end
    end)
  end

  @spec lower(FunctionPlan.t()) :: function_unit()
  def lower(%FunctionPlan{} = plan) do
    if FusionFunction.emittable?(plan) do
      FusionFunction.lower(plan)
    else
      lower_fusion_c_or_plan(plan)
    end
  end

  defp lower_fusion_c_or_plan(%FunctionPlan{} = plan) do
    fusion_c = Map.get(plan, :fusion_c)

    if is_binary(fusion_c) and fusion_c != "" do
      %{
        export_name: export_name(plan),
        module: plan.module,
        name: plan.name,
        params: param_names(plan),
        rc_required: plan.rc_required,
        body: [";; fusion_c bypass\n", fusion_c],
        imports: MapSet.new(),
        import_arities: %{}
      }
    else
      lower_plan(plan)
    end
  end

  defp lower_plan(%FunctionPlan{} = plan, opts \\ []) do
    slots = Slots.build(plan)
    fn_table = FnTable.collect(plan)
    catch_id = 0

    instr_opts = [
      rc_required: plan.rc_required,
      fn_table: fn_table,
      catch_id: catch_id,
      slots: slots,
      parent_plan: plan
    ]

    {imports, import_arities} = ImportCollect.collect(plan)

    body =
      emit_blocks(plan.blocks, slots, instr_opts)
      |> then(fn block_body ->
        if plan.rc_required do
          Frame.wrap_catch(true, block_body, catch_id)
        else
          block_body
        end
      end)
      |> IO.iodata_to_binary()

    body =
      [
        Slots.local_decls(slots),
        Frame.init_rc(slots),
        body,
        Frame.box_native_scalar_return(plan, slots),
        Frame.epilogue_release(slots),
        Frame.return_rc(slots)
      ]
      |> IO.iodata_to_binary()

    %{
      export_name: Keyword.get(opts, :export_name, export_name(plan)),
      module: plan.module,
      name: Keyword.get(opts, :name, plan.name),
      params: param_names(plan),
      rc_required: plan.rc_required,
      body: body,
      imports: imports,
      import_arities: import_arities
    }
  end

  defp emit_blocks(blocks, slots, instr_opts) do
    case blocks do
      [%Block{} = only] ->
        emit_block_body(only, slots, instr_opts)

      _ ->
        emit_state_switch_body(blocks, slots, instr_opts)
    end
  end

  defp emit_state_switch_body(blocks, slots, instr_opts) do
    plan_state = slots.plan_state_local || flunk_plan_state!(slots)
    entry_id = blocks |> List.first() |> Map.get(:id, 0)

    dispatch =
      blocks
      |> Enum.with_index()
      |> Enum.flat_map(fn {%Block{id: id} = block, idx} ->
        terminator = resolve_state_switch_terminator(block.terminator, blocks, idx)

        case_body =
          Enum.flat_map(block.instrs, &Instr.emit(&1, slots, instr_opts)) ++
            emit_state_switch_terminator(terminator, slots, instr_opts)

        [
          WasmTypes.line(
            WasmTypes.sexpr_open("if", [
              WasmTypes.sexpr("i32.eq", [
                " ",
                WasmTypes.sexpr("local.get", [plan_state]),
                " ",
                WasmTypes.sexpr("i32.const", [id])
              ])
            ])
          ),
          WasmTypes.line("(then"),
          WasmTypes.indent(case_body, 1),
          WasmTypes.line(")"),
          WasmTypes.line(")")
        ]
      end)

    [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [entry_id])
        ])
      ),
      WasmTypes.line(WasmTypes.sexpr_open("loop", [" ", @plan_loop])),
      WasmTypes.indent(
        [
          WasmTypes.line(WasmTypes.sexpr_open("block", [" ", @plan_switch_done])),
          WasmTypes.indent(dispatch, 1),
          WasmTypes.line(")"),
          WasmTypes.line(
            WasmTypes.sexpr("br_if", [
              " ",
              @plan_loop,
              " ",
              WasmTypes.sexpr("i32.ge_s", [
                " ",
                WasmTypes.sexpr("local.get", [plan_state]),
                " ",
                WasmTypes.sexpr("i32.const", [0])
              ])
            ])
          )
        ],
        1
      ),
      WasmTypes.line(")")
    ]
  end

  defp emit_block_body(%Block{instrs: instrs, terminator: term}, slots, instr_opts) do
    Enum.flat_map(instrs, &Instr.emit(&1, slots, instr_opts)) ++
      Instr.emit_terminator(term, slots, instr_opts)
  end

  defp emit_state_switch_terminator({:br, target_id}, slots, _instr_opts) do
    plan_state = slots.plan_state_local

    [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [target_id])
        ])
      ),
      WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
    ]
  end

  defp emit_state_switch_terminator({:br_if, then_id, else_id, cond_reg}, slots, _instr_opts) do
    plan_state = slots.plan_state_local
    cond = Slots.reg_name(slots, cond_reg)

    [
      WasmTypes.line(WasmTypes.sexpr_open("if", [bool_cond_wat(cond)])),
      WasmTypes.line("(then"),
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [then_id])
        ])
      ),
      WasmTypes.line(") (else"),
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [else_id])
        ])
      ),
      WasmTypes.line(")"),
      WasmTypes.line(")"),
      WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
    ]
  end

  defp emit_state_switch_terminator({:switch_tag, subject, arms, default_id}, slots, _instr_opts) do
    plan_state = slots.plan_state_local
    subj = Slots.reg_name(slots, subject)
    tag_expr = union_tag_int_wat(subj)

    arm_lines =
      Enum.flat_map(arms, fn arm ->
        tag = switch_arm_tag(arm)
        target_id = switch_arm_target(arm)

        [
          WasmTypes.line(
            WasmTypes.sexpr_open("if", [
              WasmTypes.sexpr("i32.eq", [
                " ",
                tag_expr,
                " ",
                WasmTypes.sexpr("i32.const", [tag])
              ])
            ])
          ),
          WasmTypes.line("(then"),
          WasmTypes.line(
            WasmTypes.sexpr("local.set", [
              plan_state,
              " ",
              WasmTypes.sexpr("i32.const", [target_id])
            ])
          ),
          WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done])),
          WasmTypes.line(")"),
          WasmTypes.line(")")
        ]
      end)

    arm_lines ++
      [
        WasmTypes.line(
          WasmTypes.sexpr("local.set", [
            plan_state,
            " ",
            WasmTypes.sexpr("i32.const", [default_id])
          ])
        ),
        WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
      ]
  end

  defp emit_state_switch_terminator({:ret, :fn_out}, slots, _instr_opts) do
    plan_state = slots.plan_state_local

    [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [-1])
        ])
      ),
      WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
    ]
  end

  defp emit_state_switch_terminator({:ret, reg}, slots, _instr_opts) when is_integer(reg) do
    plan_state = slots.plan_state_local

    [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          slots.fn_out_local,
          " ",
          WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])
        ])
      ),
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [-1])
        ])
      ),
      WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
    ]
  end

  defp emit_state_switch_terminator(:none, slots, _instr_opts) do
    exit_state_switch(slots)
  end

  defp emit_state_switch_terminator(_, slots, instr_opts) do
    emit_state_switch_terminator(:none, slots, instr_opts)
  end

  # Plan `:none` terminators mean "fall through to the next basic block". Only the
  # final block in a multi-block function should exit the state switch.
  defp resolve_state_switch_terminator(:none, blocks, idx) do
    case Enum.at(blocks, idx + 1) do
      %Block{id: next_id} -> {:br, next_id}
      _ -> :none
    end
  end

  defp resolve_state_switch_terminator(terminator, _blocks, _idx), do: terminator

  defp exit_state_switch(slots) do
    plan_state = slots.plan_state_local

    [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          plan_state,
          " ",
          WasmTypes.sexpr("i32.const", [-1])
        ])
      ),
      WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
    ]
  end

  defp switch_arm_tag({tag, _}), do: tag
  defp switch_arm_tag({tag, _, _}), do: tag

  defp switch_arm_target({_, block_id}), do: block_id
  defp switch_arm_target({_, block_id, _}), do: block_id

  defp flunk_plan_state!(slots) do
    raise "missing plan_state local for multi-block wasm function: #{inspect(slots)}"
  end

  defp bool_cond_wat(reg_name) do
    WasmTypes.sexpr("call", [
      WasmTypes.import_ident("runtime.as_bool"),
      " ",
      WasmTypes.sexpr("local.get", [reg_name])
    ])
  end

  defp union_tag_int_wat(reg_name) do
    WasmTypes.sexpr("call", [
      WasmTypes.import_ident("runtime.union_tag_as_int"),
      " ",
      WasmTypes.sexpr("local.get", [reg_name])
    ])
  end

  defp export_name(%FunctionPlan{module: mod, name: name}), do: WasmTypes.fn_ident(mod, name)

  defp param_names(%FunctionPlan{params: params}) do
    Enum.map(params || [], fn
      name when is_binary(name) -> name
      %{name: name} -> name
      other -> inspect(other)
    end)
  end
end
