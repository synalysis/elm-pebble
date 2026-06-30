defmodule Elmc.WorkerRcFailTest do
  use ExUnit.Case, async: false

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)
  @game_2048_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "worker emits allocation-free RC failure logging and last-fail readers" do
    project_dir = Path.expand("tmp/worker_rc_fail_project", __DIR__)
    out_dir = Path.expand("tmp/worker_rc_fail_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@game_2048_main))
    File.write!(Path.join(project_dir, "elm.json"), File.read!(@fixture_elm_json))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

    worker_c = File.read!(Path.join(out_dir, "c/elmc_worker.c"))
    worker_h = File.read!(Path.join(out_dir, "c/elmc_worker.h"))

    assert worker_h =~ "elmc_worker_last_fail_code(void)"
    assert worker_h =~ "elmc_worker_last_fail_line(void)"
    assert worker_c =~ "ELMC_WORKER_LOG_RC_FAIL"
    assert worker_c =~ ~s/APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC %s RC %u line %u"/
    assert worker_c =~ "elmc_worker_last_fail_code(void)"
    assert worker_c =~ "elmc_rc_fail_code()"
    assert worker_c =~ "elmc_last_fail_line"
    refute worker_c =~ "ELMC_TAKE_OR_RETURN"
    assert worker_c =~ "elmc_cmd_queue_normalize(&pending"
    assert worker_c =~ "List spine cells were released in the loop"
  end
end
