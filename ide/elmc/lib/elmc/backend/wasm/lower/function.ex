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
    # Prefer Bool first so `\_ -> True` keeps native_bool boxing via new_bool.
    # Annotating Int first treated bool_lit const 1 as native_int, deleted the
    # scalar marker, and returned raw 1 — stringAll's intValue(1) hit UNIT.
    bool_plan = NativeReturn.annotate(lambda, %{type: "Bool"})

    if Map.get(bool_plan, :native_scalar_return) == :native_bool do
      bool_plan
    else
      int_plan = NativeReturn.annotate(lambda, %{type: "Int"})

      if Map.get(int_plan, :native_scalar_return) == :native_int do
        # Wasm Int closure bodies already box via runtime.new_int; running
        # box_native_scalar_return would treat the handle in $fn_out as a raw i32.
        %{int_plan | native_scalar_return: nil, native_scalar_value_return: nil}
      else
        int_plan
      end
    end
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
      parent_plan: plan,
      native_scalar_out: Map.get(plan, :native_scalar_return)
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

    memo? = top_level_value_memoizable?(plan)

    body =
      [
        Slots.local_decls(slots),
        Frame.init_rc(slots),
        if(memo?, do: emit_value_cache_lookup(plan, slots), else: []),
        body,
        Frame.box_native_scalar_return(plan, slots),
        Frame.epilogue_release(slots),
        if(memo?, do: emit_value_cache_store(plan, slots), else: []),
        Frame.return_rc(slots)
      ]
      |> IO.iodata_to_binary()

    imports =
      if memo? do
        imports
        |> MapSet.put("runtime.value_cache_get")
        |> MapSet.put("runtime.value_cache_put")
      else
        imports
      end

    import_arities =
      if memo? do
        import_arities
        |> Map.put_new("runtime.value_cache_get", 2)
        |> Map.put_new("runtime.value_cache_put", 2)
      else
        import_arities
      end

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

  # Zero-arity top-level values (e.g. Scene3d.Primitives.sphere) must be
  # computed once. Without memoization, Entity.sphere rebuilds a 72×72 mesh
  # on every call (HeroScene: 23 spheres → 23× collectBumpy).
  # Note: some value plans have rc_required=false but still use the RC ABI.
  defp top_level_value_memoizable?(%FunctionPlan{} = plan) do
    length(plan.params || []) == 0
  end

  defp value_cache_id(%FunctionPlan{module: mod, name: name}) do
    :erlang.phash2({mod, name}, 2_147_483_647)
  end

  defp emit_value_cache_lookup(plan, slots) do
    get = "runtime.value_cache_get" |> WasmTypes.import_ident()
    scratch = Slots.int_array_scratch_offset()
    id = value_cache_id(plan)

    [
      WasmTypes.line(
        WasmTypes.sexpr("drop", [
          " ",
          WasmTypes.sexpr("call", [
            get,
            " ",
            WasmTypes.sexpr("i32.const", [id]),
            " ",
            WasmTypes.sexpr("i32.const", [scratch])
          ])
        ])
      ),
      WasmTypes.line(
        WasmTypes.sexpr("local.set", [
          slots.fn_out_local,
          " ",
          WasmTypes.sexpr("i32.load", [
            " offset=#{scratch} ",
            WasmTypes.sexpr("i32.const", [0])
          ])
        ])
      ),
      WasmTypes.line(
        WasmTypes.sexpr("if", [
          WasmTypes.sexpr("i32.ne", [
            " ",
            WasmTypes.sexpr("local.get", [slots.fn_out_local]),
            " ",
            WasmTypes.sexpr("i32.const", [0])
          ]),
          " (then ",
          WasmTypes.sexpr("return", [
            " ",
            WasmTypes.sexpr("local.get", [slots.rc_local]),
            " ",
            WasmTypes.sexpr("local.get", [slots.fn_out_local])
          ]),
          ")"
        ])
      )
    ]
  end

  defp emit_value_cache_store(plan, slots) do
    put = "runtime.value_cache_put" |> WasmTypes.import_ident()
    id = value_cache_id(plan)

    [
      WasmTypes.line(
        WasmTypes.sexpr("drop", [
          " ",
          WasmTypes.sexpr("call", [
            put,
            " ",
            WasmTypes.sexpr("i32.const", [id]),
            " ",
            WasmTypes.sexpr("local.get", [slots.fn_out_local])
          ])
        ])
      )
    ]
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
    plan = Keyword.fetch!(instr_opts, :parent_plan)

    dispatch =
      blocks
      |> Enum.with_index()
      |> Enum.flat_map(fn {%Block{id: id} = block, idx} ->
        terminator = resolve_state_switch_terminator(block.terminator, blocks, idx)

        case_body =
          case self_tail_call(block, terminator, blocks, plan) do
            {:tco, prefix, args} ->
              Enum.flat_map(prefix, &Instr.emit(&1, slots, instr_opts)) ++
                emit_self_tail_restart(args, entry_id, slots)

            :none ->
              Enum.flat_map(block.instrs, &Instr.emit(&1, slots, instr_opts)) ++
                emit_state_switch_terminator(terminator, slots, instr_opts)
          end

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

  # Trailing self call_fn jumping to a merge — treat as tail call only when
  # this looks like list recursion (an arg is produced by list_tail / payload
  # somewhere in the function, or this block peels a list). Broad TCO incorrectly
  # rewrote Pages.Internal.Platform.update into an infinite restart loop.
  #
  # Fallible self-calls are often wrapped as catch_begin / call_fn / catch_end;
  # those wrappers must not block recognition (BoundingBox3d.aggregateOfHelp).
  defp self_tail_call(%Block{instrs: instrs}, {:br, _join_id}, blocks, plan) do
    case trailing_self_call(instrs, plan) do
      {:ok, prefix, args} ->
        if list_recursion_self_call?(instrs, args, blocks) do
          {:tco, prefix, args}
        else
          :none
        end

      :none ->
        :none
    end
  end

  defp self_tail_call(_block, _terminator, _blocks, _plan), do: :none

  defp trailing_self_call(instrs, plan) do
    case Enum.reverse(instrs) do
      [%{op: :catch_end} | [%{op: :call_fn, args: %{module: mod, name: name, args: args}} | rest]]
      when mod == plan.module and name == plan.name and is_list(args) ->
        prefix_rev =
          case rest do
            [%{op: :catch_begin} | rest2] -> rest2
            _ -> rest
          end

        {:ok, Enum.reverse(prefix_rev), args}

      [%{op: :call_fn, args: %{module: mod, name: name, args: args}} | rest]
      when mod == plan.module and name == plan.name and is_list(args) ->
        {:ok, Enum.reverse(rest), args}

      _ ->
        :none
    end
  end

  defp list_recursion_self_call?(instrs, args, blocks) do
    produced = list_peel_produced_regs(blocks)
    arg_from_list? = Enum.any?(args, &MapSet.member?(produced, &1))
    arg_from_list? or list_peel_instrs?(instrs)
  end

  defp list_peel_produced_regs(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs} ->
      Enum.flat_map(instrs, fn
        %{op: :call_runtime, dest: dest, args: %{builtin: builtin}}
        when is_integer(dest) and
               builtin in [:list_tail, :maybe_just_payload, :list_head, :list_drop] ->
          [dest]

        # maybe_just_payload is lowered as retain + view_peel (borrow view).
        %{op: :call_runtime, dest: dest, args: %{view_peel: peel}}
        when is_integer(dest) and peel in [:maybe_just_payload, :union_payload] ->
          [dest]

        _ ->
          []
      end)
    end)
    |> MapSet.new()
  end

  defp list_peel_instrs?(instrs) do
    Enum.any?(instrs, fn
      %{op: :test_list_empty} ->
        true

      %{op: :call_runtime, args: %{builtin: builtin}}
      when builtin in [:list_tail, :list_head, :list_is_empty, :maybe_just_payload] ->
        true

      %{op: :call_runtime, args: %{view_peel: peel}}
      when peel in [:maybe_just_payload, :union_payload] ->
        true

      _ ->
        false
    end)
  end

  defp emit_self_tail_restart(args, entry_id, slots) do
    plan_state = slots.plan_state_local
    roots_scratch = Slots.int_array_scratch_offset()
    import_release_unless =
      "runtime.release_unless_reachable_from_roots" |> WasmTypes.import_ident()

    # Spill previous params, assign new ones, then release temps that are not
    # reachable from the restarted params.
    #
    # Owned/reg temps often alias values just list_cons'd into a new param
    # (e.g. Entity.collectNodes). Plain release frees those nodes while the
    # accumulating cons spine still points at them → Group kids become null and
    # Scene3d getViewBounds sees only EmptyNode. Use reachability from the new
    # params (host marks the gen once per roots fingerprint).
    spill_olds_aside =
      Enum.map(0..(slots.params - 1)//1, fn index ->
        # Keep [0, params) free for new-param roots; spill olds just after.
        offset = roots_scratch + 4 * (slots.params + index)

        WasmTypes.line(
          WasmTypes.sexpr("i32.store", [
            " offset=#{offset} ",
            WasmTypes.sexpr("i32.const", [0]),
            " ",
            WasmTypes.sexpr("local.get", ["$param#{index}"])
          ])
        )
      end)

    assigns =
      args
      |> Enum.with_index()
      |> Enum.flat_map(fn {arg_reg, index} ->
        [
          WasmTypes.line(
            WasmTypes.sexpr("local.set", [
              "$param#{index}",
              " ",
              format_restart_arg(arg_reg, slots)
            ])
          )
        ]
      end)

    store_new_roots = emit_tco_store_param_roots(slots, roots_scratch)

    release_olds =
      Enum.flat_map(0..(slots.params - 1)//1, fn index ->
        old_offset = roots_scratch + 4 * (slots.params + index)

        old_load =
          WasmTypes.sexpr("i32.load", [
            " offset=#{old_offset} ",
            WasmTypes.sexpr("i32.const", [0])
          ])

        [
          WasmTypes.line(
            WasmTypes.sexpr("if", [
              WasmTypes.sexpr("i32.ne", [
                " ",
                old_load,
                " ",
                WasmTypes.sexpr("i32.const", [0])
              ]),
              " (then ",
              WasmTypes.sexpr("drop", [
                " ",
                WasmTypes.sexpr("call", [
                  import_release_unless,
                  " ",
                  old_load,
                  " ",
                  WasmTypes.sexpr("i32.const", [roots_scratch]),
                  " ",
                  WasmTypes.sexpr("i32.const", [slots.params])
                ])
              ]),
              ")"
            ])
          )
        ]
      end)

    release_owned = emit_tco_release_owned(slots, roots_scratch)
    release_regs = emit_tco_release_regs(slots, roots_scratch)

    clear_owned =
      case slots.owned_count do
        n when is_integer(n) and n > 0 ->
          Enum.map(0..(n - 1)//1, fn idx ->
            WasmTypes.line(
              WasmTypes.sexpr("local.set", [
                Slots.owned_local(slots, idx),
                " ",
                WasmTypes.sexpr("i32.const", [0])
              ])
            )
          end)

        _ ->
          []
      end

    spill_olds_aside ++
      assigns ++
      store_new_roots ++
      release_olds ++
      release_owned ++
      release_regs ++
      clear_owned ++
      [
        WasmTypes.line(
          WasmTypes.sexpr("local.set", [
            plan_state,
            " ",
            WasmTypes.sexpr("i32.const", [entry_id])
          ])
        ),
        WasmTypes.line(WasmTypes.sexpr("br", [" ", @plan_switch_done]))
      ]
  end

  defp emit_tco_store_param_roots(slots, roots_scratch) do
    Enum.map(0..(slots.params - 1)//1, fn index ->
      offset = roots_scratch + 4 * index

      WasmTypes.line(
        WasmTypes.sexpr("i32.store", [
          " offset=#{offset} ",
          WasmTypes.sexpr("i32.const", [0]),
          " ",
          WasmTypes.sexpr("local.get", ["$param#{index}"])
        ])
      )
    end)
  end

  defp emit_tco_release_owned(%{owned_count: n}, _roots_scratch)
       when not is_integer(n) or n <= 0,
       do: []

  defp emit_tco_release_owned(slots, roots_scratch) do
    import_name =
      "runtime.release_unless_reachable_from_roots" |> WasmTypes.import_ident()

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
                WasmTypes.sexpr("i32.const", [slots.params])
              ])
            ]),
            ")"
          ])
        )
      ]
    end)
    |> Enum.reverse()
  end

  defp emit_tco_release_regs(%{reg_locals: regs} = slots, roots_scratch)
       when map_size(regs) > 0 do
    import_name =
      "runtime.release_unless_reachable_from_roots" |> WasmTypes.import_ident()

    regs
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(fn reg ->
      local = Slots.reg_name(slots, reg)

      [
        WasmTypes.line(
          WasmTypes.sexpr("if", [
            WasmTypes.sexpr("i32.ne", [
              " ",
              WasmTypes.sexpr("local.get", [local]),
              " ",
              WasmTypes.sexpr("i32.const", [0])
            ]),
            " (then ",
            WasmTypes.sexpr("drop", [
              " ",
              WasmTypes.sexpr("call", [
                import_name,
                " ",
                WasmTypes.sexpr("local.get", [local]),
                " ",
                WasmTypes.sexpr("i32.const", [roots_scratch]),
                " ",
                WasmTypes.sexpr("i32.const", [slots.params])
              ])
            ]),
            ")"
          ])
        )
      ]
    end)
  end

  defp emit_tco_release_regs(_slots, _roots_scratch), do: []

  defp format_restart_arg(reg, slots) when is_integer(reg) do
    WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])
  end

  defp format_restart_arg(other, _slots) do
    raise "self-tail restart expects register args, got: #{inspect(other)}"
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

  defp emit_state_switch_terminator({:ret, reg}, slots, instr_opts) when is_integer(reg) do
    plan_state = slots.plan_state_local

    publish = Instr.publish_fn_out(slots, reg, instr_opts)

    publish ++
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
