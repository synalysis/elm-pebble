defmodule Elmc.WorkerSubscriptionSlotsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Worker

  @simple_project Path.expand("fixtures/simple_project", __DIR__)
  @pebble_surface Path.expand("fixtures/pebble_surface_project", __DIR__)
  @game_2048_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  defp compile_worker_header!(project_dir, opts \\ []) do
    out_dir = Path.expand("tmp/worker_slots_#{:erlang.phash2({project_dir, opts})}", __DIR__)
    File.rm_rf!(out_dir)

    {:ok, _} =
      Elmc.compile(project_dir, Map.merge(%{out_dir: out_dir, entry_module: "Main"}, Map.new(opts)))

    File.read!(Path.join(out_dir, "c/elmc_worker.h"))
  end

  defp compile_game_2048_header! do
    project_dir = Path.expand("tmp/worker_slots_game_2048", __DIR__)
    File.rm_rf!(project_dir)
    File.cp_r!(@simple_project, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@game_2048_main))
    compile_worker_header!(project_dir)
  end

  defp sub_tag_slots(header) do
    [_, count] = Regex.run(~r/#define ELMC_WORKER_SUB_TAG_SLOTS (\d+)/, header)
    String.to_integer(count)
  end

  test "simple_project uses compact tag slots for tick and accel only" do
    header = compile_worker_header!(@simple_project)

    assert sub_tag_slots(header) == 2
    assert header =~ "#define ELMC_WORKER_MAX_BUTTON_RAW_SUBS 3"
    assert header =~ "#define ELMC_WORKER_SLOT_ACCEL_TAP"
    assert header =~ "#define ELMC_WORKER_SLOT_SECOND_CHANGE"
    refute header =~ "#define ELMC_WORKER_SUB_TAG_SLOTS 32"
  end

  test "game_2048 template sizes button raw table to four presses" do
    header = compile_game_2048_header!()

    assert sub_tag_slots(header) == 1
    assert header =~ "#define ELMC_WORKER_MAX_BUTTON_RAW_SUBS 4"
    refute header =~ "#define ELMC_WORKER_SLOT_"
  end

  test "pebble surface project compacts many subscriptions into dense slots" do
    header = compile_worker_header!(@pebble_surface, strip_dead_code: false)

    assert header =~ "#define ELMC_WORKER_SLOT_FRAME"
    assert header =~ "#define ELMC_WORKER_MAX_BUTTON_RAW_SUBS"

    slots = sub_tag_slots(header)
    assert slots < 32
    assert slots >= 10
  end

  test "subscription analysis derives compact layout from subscriptions IR" do
    {:ok, %{ir: ir}} = Elmc.compile(@simple_project, %{out_dir: "build/worker_slots_analysis"})
    layout = Worker.subscription_analysis(ir, "Main")

    assert layout.compact
    assert layout.sub_tag_slots == 2
    assert layout.button_raw_count == 3
    assert Map.has_key?(layout.slot_map, "ELMC_SUBSCRIPTION_SECOND_CHANGE")
    assert Map.has_key?(layout.slot_map, "ELMC_SUBSCRIPTION_ACCEL_TAP")
  end
end
