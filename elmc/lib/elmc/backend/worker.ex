defmodule Elmc.Backend.Worker do
  @moduledoc """
  Thin C worker adapter for Elm TEA init/update loops.

  Layout analysis and shared TEA/cmd-queue C live in `Plan.Worker.{Layout,Emit}`;
  this module only wires app entry calls (`init` / `update` / `subscriptions`)
  and writes `elmc_worker.{h,c}`.
  """
  alias Elmc.Types, as: Types


  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.FunctionCallAbi
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Worker.Emit, as: WorkerEmit
  alias Elmc.Backend.Plan.Worker.Layout, as: WorkerLayout
  alias Elmc.Types

  @spec write_worker_adapter(IR.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, Types.file_error()}
  def write_worker_adapter(%IR{} = ir, out_dir, entry_module, opts \\ []) do
    c_dir = Path.join(out_dir, "c")
    analysis = subscription_analysis(ir, entry_module)

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_worker.h"), worker_header(analysis, opts)),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_worker.c"),
             ir |> worker_source(entry_module, analysis, opts) |> CSource.format()
           ) do
      :ok
    end
  end

  @spec subscription_analysis(IR.t(), String.t()) :: WorkerLayout.t()
  def subscription_analysis(%IR{} = ir, entry_module), do: WorkerLayout.analyze(ir, entry_module)

  @spec worker_header(WorkerLayout.t(), keyword() | Types.compile_options()) ::
          String.t()
  defp worker_header(analysis, opts) do
    last_dispatch_cmd_cap = last_dispatch_cmd_cap(opts)
    slot_defines = WorkerEmit.worker_slot_defines(analysis)

    """
    #ifndef ELMC_WORKER_H
    #define ELMC_WORKER_H

    #include "elmc_generated.h"

    #define ELMC_WORKER_MAX_BUTTON_RAW_SUBS #{analysis.button_raw_subs}
    #define ELMC_WORKER_SUB_TAG_SLOTS #{analysis.sub_tag_slots}
    #{slot_defines}

    typedef struct {
      elmc_int_t button_id;
      elmc_int_t event;
      elmc_int_t msg_tag;
    } ElmcButtonRawSub;

    #ifndef ELMC_WORKER_LAST_DISPATCH_CMD_CAP
    #define ELMC_WORKER_LAST_DISPATCH_CMD_CAP #{last_dispatch_cmd_cap}
    #endif

    typedef struct {
      int64_t kind;
      int64_t p0;
      int64_t p1;
      int64_t p2;
      int64_t p3;
      int64_t p4;
      int64_t p5;
      char text[128];
    } ElmcWorkerDispatchCmd;

    typedef struct {
      ElmcValue *model;
      ElmcValue *pending_cmd;
    #if ELMC_WORKER_LAST_DISPATCH_CMD_CAP > 0
      ElmcWorkerDispatchCmd last_dispatch_cmds[ELMC_WORKER_LAST_DISPATCH_CMD_CAP];
      int last_dispatch_cmd_count;
    #endif
      int64_t subscriptions;
      elmc_int_t sub_msg_tags[ELMC_WORKER_SUB_TAG_SLOTS];
      ElmcButtonRawSub button_raw_subs[ELMC_WORKER_MAX_BUTTON_RAW_SUBS];
      int button_raw_sub_count;
      int dispatch_needs_render;
    } ElmcWorkerState;

    int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags);
    int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg);
    int elmc_worker_dispatch_needs_render(ElmcWorkerState *state);
    ElmcValue *elmc_worker_model(ElmcWorkerState *state);
    ElmcValue *elmc_worker_pending_cmds_borrow(ElmcWorkerState *state);
    int elmc_worker_last_dispatch_cmd_count(ElmcWorkerState *state);
    int elmc_worker_last_dispatch_cmd_at(ElmcWorkerState *state, int index, ElmcWorkerDispatchCmd *out_cmd);
    ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
    int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
    elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag);
    elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event);
    elmc_int_t elmc_worker_last_fail_code(void);
    elmc_int_t elmc_worker_last_fail_line(void);
    void elmc_worker_deinit(ElmcWorkerState *state);

    #endif
    """
  end

  @spec last_dispatch_cmd_cap(keyword()) :: Types.ir_expr()

  defp last_dispatch_cmd_cap(opts) do
    opts = Map.new(opts)

    if Map.get(opts, :pebble_int32) == true and Map.get(opts, :prod) == true do
      0
    else
      8
    end
  end

  @spec worker_source(
          ElmEx.IR.t(),
          String.t(),
          WorkerLayout.t(),
          keyword() | Types.compile_options()
        ) :: String.t()
  defp worker_source(ir, entry_module, analysis, opts) do
    module =
      Enum.find(ir.modules, fn mod ->
        mod.name == entry_module
      end)

    declarations = if module, do: module.declarations, else: []
    has_init = Enum.any?(declarations, &(&1.kind == :function and &1.name == "init"))
    has_update = Enum.any?(declarations, &(&1.kind == :function and &1.name == "update"))

    has_subscriptions =
      Enum.any?(declarations, &(&1.kind == :function and &1.name == "subscriptions"))

    safe_module = entry_module |> String.replace(".", "_")
    decl_map = IRQueries.function_decl_map(ir)

    init_call =
      if has_init do
        worker_entry_call(safe_module, "init", entry_module, decl_map, ["flags"], """
          if (init_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker init", init_rc);
            elmc_release(result);
            return -2;
          }
        """, opts)
      else
        """
        (void)flags;
          ElmcValue *result = elmc_int_zero();
        """
      end

    init_missing_guard = if has_init, do: "", else: "  return -3;\n"

    update_call =
      if has_update do
        worker_entry_call(safe_module, "update", entry_module, decl_map, ["msg", "state->model"], """
          if (update_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker update", update_rc);
            elmc_release(result);
            return -2;
          }
        """, opts)
      else
        """
        (void)msg;
          ElmcValue *result = elmc_int_zero();
        """
      end

    update_missing_guard = if has_update, do: "", else: "  return -4;\n"

    subscriptions_call =
      if has_subscriptions do
        worker_entry_call(
          safe_module,
          "subscriptions",
          entry_module,
          decl_map,
          ["state->model"],
          """
            if (sub_rc != RC_SUCCESS) {
              ELMC_WORKER_LOG_RC_FAIL("worker subscriptions", sub_rc);
              elmc_release(result);
              return 0;
            }
          """,
          opts
        )
      else
        """
        ElmcValue *result = elmc_int_zero();
        """
      end

    dispatch_subscriptions_refresh =
      if has_subscriptions and Map.get(analysis, :model_dependent?, true) do
        "  if (state->dispatch_needs_render) {\n    state->subscriptions = compute_subscriptions(state);\n  }\n"
      else
        ""
      end

    """
    #{WorkerEmit.tea_preamble_c()}

    #{WorkerEmit.cmd_queue_runtime_c()}

    #{WorkerEmit.sub_tag_slot_fn(analysis)}

    #{WorkerEmit.subscription_runtime_c()}

    #{WorkerEmit.compute_subscriptions_fn(subscriptions_call)}

    #{WorkerEmit.init_fn(init_call, init_missing_guard)}

    #{WorkerEmit.dispatch_fn(update_call, update_missing_guard, dispatch_subscriptions_refresh)}

    #{WorkerEmit.tea_host_api_c()}
    """
  end

  @worker_entry_rc_vars %{"subscriptions" => "sub_rc"}

  @spec worker_entry_call(String.t(), String.t(), String.t(), Types.decl_map(), Types.expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp worker_entry_call(safe_module, fun_name, entry_module, decl_map, arg_exprs, on_fail_body, opts) do
    rc_var = Map.get(@worker_entry_rc_vars, fun_name, "#{fun_name}_rc")
    decl = Map.get(decl_map, {entry_module, fun_name})

    call =
      if is_map(decl) and FunctionCallAbi.direct_entry_abi?(decl, entry_module, decl_map, opts) do
        args = Enum.join(arg_exprs, ", ")
        "RC #{rc_var} = elmc_fn_#{safe_module}_#{fun_name}(&result, #{args});"
      else
        argc = length(arg_exprs)
        args_init = Enum.join(arg_exprs, ", ")

        """
        ElmcValue *args[] = { #{args_init} };
          RC #{rc_var} = elmc_fn_#{safe_module}_#{fun_name}(&result, args, #{argc});
        """
        |> String.trim()
      end

    """
    ElmcValue *result = NULL;
      #{call}
      #{String.trim(on_fail_body)}
    """
  end
end
