defmodule Elmc.WorkerAdapterTest do
  use ExUnit.Case

  test "generated worker adapter runs init and update loop" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for worker adapter C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/worker_adapter", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/worker_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_worker.h"
      #include <stdio.h>

      int main(void) {
        ElmcWorkerState state = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_worker_init(&state, flags) != 0) return 2;
        elmc_release(flags);

        ElmcValue *init_cmd = elmc_worker_take_cmd(&state);
        if (!init_cmd) return 21;
        elmc_release(init_cmd);

        ElmcValue *increment = elmc_new_int(1);
        if (elmc_worker_dispatch(&state, increment) != 0) return 3;
        elmc_release(increment);

        ElmcValue *next_cmd = elmc_worker_take_cmd(&state);
        if (!next_cmd || elmc_as_int(next_cmd) != 0) return 23;
        elmc_release(next_cmd);

        ElmcValue *model = elmc_worker_model(&state);
        if (!model) return 4;
        if (model->tag != ELMC_TAG_TUPLE2 || model->payload == NULL) return 24;
        ElmcTuple2 *model_pair = (ElmcTuple2 *)model->payload;
        if (!model_pair || !model_pair->first) return 25;
        printf("model=%lld\\n", (long long)elmc_as_int(model_pair->first));
        elmc_release(model);
        printf("subs=%lld\\n", (long long)elmc_worker_subscriptions(&state));

        elmc_worker_deinit(&state);
        printf("%llu %llu\\n",
               (unsigned long long)elmc_rc_allocated_count(),
               (unsigned long long)elmc_rc_released_count());
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "worker_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        "-I#{Path.join(out_dir, "ports")}",
        "-I#{Path.join(out_dir, "c")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        Path.join(out_dir, "ports/elmc_ports.c"),
        Path.join(out_dir, "c/elmc_generated.c"),
        Path.join(out_dir, "c/elmc_worker.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
    assert String.contains?(run_out, "model=1")
    assert String.contains?(run_out, "subs=31")

    [alloc, rel] =
      run_out
      |> String.split("\n", trim: true)
      |> List.last()
      |> String.split(" ")

    assert String.to_integer(alloc) > 0
    assert String.to_integer(alloc) == String.to_integer(rel)
  end
end
