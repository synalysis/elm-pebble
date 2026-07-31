defmodule Elmc.Backend.Worker do
  @moduledoc """
  Thin C worker adapter for Elm TEA init/update loops.

  Layout analysis lives in `Plan.Worker.Layout`; TEA host shells are lowered to
  `Plan.Worker.HostPlan`, checked by `Plan.Worker.Host.Verify`, and emitted by
  `Plan.Worker.Host.Emit`. Pure cmd-queue helpers live in `Elmc.Runtime.CmdQueue`;
  extract/snapshot and subscription slot C remain in `Plan.Worker.Emit`.
  """
  alias Elmc.Types
  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.Plan.Worker.HostPlan
  alias Elmc.Backend.Plan.Worker.Emit, as: WorkerEmit
  alias Elmc.Backend.Plan.Worker.Host.Emit, as: HostEmit
  alias Elmc.Backend.Plan.Worker.Host.Lower, as: HostLower
  alias Elmc.Backend.Plan.Worker.Host.Verify, as: HostVerify
  alias Elmc.Backend.Plan.Worker.Layout, as: WorkerLayout

  @spec write_worker_adapter(IR.t(), String.t(), String.t(), map() | keyword()) ::
          :ok | {:error, Types.file_error()}
  def write_worker_adapter(%IR{} = ir, out_dir, entry_module, opts \\ []) do
    c_dir = Path.join(out_dir, "c")
    layout = subscription_analysis(ir, entry_module)
    host_plan = HostLower.lower(ir, entry_module, layout, opts)

    case HostVerify.verify(host_plan) do
      :ok -> :ok
      {:error, reason} -> raise "host plan verify failed: #{inspect(reason)}"
    end

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_worker.h"), worker_header(host_plan, opts)),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_worker.c"),
             host_plan |> HostEmit.worker_source() |> CSource.format()
           ) do
      :ok
    end
  end

  @spec subscription_analysis(IR.t(), String.t()) :: WorkerLayout.t()
  def subscription_analysis(%IR{} = ir, entry_module), do: WorkerLayout.analyze(ir, entry_module)

  @spec worker_header(HostPlan.t(), keyword() | Types.compile_options()) :: String.t()
  defp worker_header(host_plan, opts) do
    analysis = Map.get(host_plan, :layout, host_plan)
    last_dispatch_cmd_cap = last_dispatch_cmd_cap(host_plan, opts)
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

  defp last_dispatch_cmd_cap(%{last_dispatch_cmd_cap: cap}, _opts) when is_integer(cap), do: cap
end
