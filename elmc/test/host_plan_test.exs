defmodule Elmc.HostPlanTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Worker.Host.Emit, as: HostEmit
  alias Elmc.Backend.Plan.Worker.Host.Lower, as: HostLower
  alias Elmc.Backend.Plan.Worker.HostPlan
  alias Elmc.Backend.Worker

  @simple_project Path.expand("fixtures/simple_project", __DIR__)

  defp lower_simple!(opts \\ []) do
    {:ok, %{ir: ir}} =
      Elmc.compile(@simple_project, %{out_dir: "build/host_plan_test", entry_module: "Main"})

    layout = Worker.subscription_analysis(ir, "Main")
    HostLower.lower(ir, "Main", layout, opts)
  end

  test "lowers init/update/subscriptions entry specs for simple_project" do
    plan = lower_simple!()

    assert %HostPlan{entry_module: "Main"} = plan
    assert plan.init.present?
    assert plan.update.present?
    assert plan.subscriptions.present?
    refute plan.model_dependent_subs?
    assert plan.last_dispatch_cmd_cap == 8
    assert plan.init.call.fun == "init"
    assert plan.init.call.arg_exprs == ["flags"]
    assert plan.update.call.arg_exprs == ["msg", "state->model"]
    assert plan.subscriptions.call.arg_exprs == ["state->model"]
    assert plan.init.call.call_c =~ "elmc_fn_Main_init"
    assert plan.update.call.on_fail_c =~ "worker update"
  end

  test "prod pebble_int32 build caps last_dispatch_cmd at zero" do
    plan = lower_simple!(pebble_int32: true, prod: true)
    assert plan.last_dispatch_cmd_cap == 0
  end

  test "emit composes shared runtime and TEA host shells from HostPlan" do
    plan = lower_simple!()
    source = HostEmit.worker_source(plan)

    assert source =~ "elmc_cmd_queue_normalize"
    assert source =~ "elmc_worker_apply_sub"
    assert source =~ "static int64_t compute_subscriptions"
    assert source =~ "int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags)"
    assert source =~ "int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg)"
    assert source =~ "elmc_fn_Main_init(&result, flags)"
    assert source =~ "elmc_fn_Main_update(&result, msg, state->model)"
    assert source =~ "elmc_fn_Main_subscriptions(&result, state->model)"

    dispatch_body =
      source
      |> String.split("int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {")
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_worker_model(ElmcWorkerState *state) {")
      |> hd()

    refute dispatch_body =~ "compute_subscriptions"
  end
end
