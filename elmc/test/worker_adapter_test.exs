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
      #include "elmc_runtime.h"
      #include <stdio.h>

      static ElmcValue *launch_context(void) {
        ElmcValue *reason = elmc_new_int_take(1); /* Pebble.Platform.LaunchSystem constructor tag */
        ElmcValue *watch_model = elmc_new_string_take("");
        ElmcValue *watch_profile_id = elmc_new_string_take("");
        ElmcValue *screen = elmc_int_zero();
        ElmcValue *has_microphone = elmc_new_int_take(0);
        ElmcValue *has_compass = elmc_new_int_take(0);
        ElmcValue *supports_health = elmc_new_int_take(0);
        const char *names[] = {
          "hasCompass", "hasMicrophone", "reason", "screen",
          "supportsHealth", "watchModel", "watchProfileId"
        };
        ElmcValue *values[] = {
          has_compass, has_microphone, reason, screen,
          supports_health, watch_model, watch_profile_id
        };
        return elmc_record_new_take_value(7, names, values);
      }

      int main(void) {
        ElmcWorkerState state = {0};
        ElmcValue *context = launch_context();
        if (elmc_worker_init(&state, context) != 0) return 2;
        elmc_release(context);

        for (int i = 0; i < 16; i++) {
          ElmcValue *init_cmd = elmc_worker_take_cmd(&state);
          if (!init_cmd) return 21;
          int done = (init_cmd->tag == ELMC_TAG_INT || init_cmd->tag == ELMC_TAG_BOOL) && elmc_as_int(init_cmd) == 0;
          elmc_release(init_cmd);
          if (done) break;
          if (i == 15) return 22;
        }

        ElmcValue *model_after_init = elmc_worker_model(&state);
        if (!model_after_init) return 4;
        elmc_int_t init_value = ELMC_RECORD_GET_INDEX_INT(model_after_init, 0);
        elmc_release(model_after_init);

        ElmcValue *increment = elmc_new_int_take(1);
        if (elmc_worker_dispatch(&state, increment) != 0) return 3;
        elmc_release(increment);

        ElmcValue *next_cmd = elmc_worker_take_cmd(&state);
        if (!next_cmd || elmc_as_int(next_cmd) != 0) return 23;
        elmc_release(next_cmd);

        ElmcValue *model = elmc_worker_model(&state);
        if (!model) return 4;
        if (model->tag != ELMC_TAG_RECORD || model->payload == NULL) return 24;
        elmc_int_t counter = ELMC_RECORD_GET_INDEX_INT(model, 0);
        printf("model=%lld\\n", (long long)(counter - init_value));
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
        Path.join(out_dir, "c/elmc_pebble.c"),
        Path.join(out_dir, "c/elmc_worker.c"),
        harness_path,
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
    assert String.contains?(run_out, "model=0")
    assert String.contains?(run_out, "subs=16384")

    [alloc, rel] =
      run_out
      |> String.split("\n", trim: true)
      |> List.last()
      |> String.split(" ")

    assert String.to_integer(alloc) > 0
    assert abs(String.to_integer(alloc) - String.to_integer(rel)) <= 24
  end
end
