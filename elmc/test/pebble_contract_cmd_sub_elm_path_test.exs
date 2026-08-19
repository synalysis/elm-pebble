defmodule Elmc.PebbleContractCmdSubElmPathTest do
  @moduledoc """
  Elm surface fixture → elmc generated constants and host-queued Cmd kinds.

  Complements table parity tests by proving real Elm call sites lower to the
  contract `ELMC_PEBBLE_CMD_*` / `ELMC_SUBSCRIPTION_*` values the runtime uses.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.CachedCompile
  alias Elmx.Pebble.Contract.CmdSub

  @fixture Path.expand("fixtures/pebble_surface_project", __DIR__)
  @support_dir Path.expand("support", __DIR__)
  @harness_helpers_c Path.join(@support_dir, "elmc_harness_helpers.c")

  @surface_cmd_ids Enum.reject(CmdSub.cmd_ids(), &(&1 == :none))

  @surface_sub_ids [
    :second_change,
    :hour_change,
    :minute_change,
    :day_change,
    :month_change,
    :year_change,
    :accel_tap,
    :battery,
    :connection,
    :frame,
    :button_raw,
    :accel_data,
    :app_focus,
    :compass,
    :dictation,
    :health,
    :animation_finished,
    :backlight,
    :screen_change,
    :speaker_finished,
    :unobstructed_area,
    :appmessage,
    :touch_tap,
    :touch_pan,
    :touch_swipe
  ]

  setup_all do
    out_dir = Path.expand("tmp/pebble_surface_cmd_sub_path", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             CachedCompile.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    {:ok, out_dir: out_dir}
  end

  test "surface fixture generated C contains every contract cmd macro", %{out_dir: out_dir} do
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    for id <- @surface_cmd_ids do
      row = CmdSub.cmd!(id)
      assert generated_c =~ row.c_macro, "elmc_generated.c missing #{row.c_macro} from surface init"
    end
  end

  test "surface subscriptions function contains every public contract sub mask", %{out_dir: out_dir} do
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    subs_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_subscriptions")

    for id <- @surface_sub_ids do
      row = CmdSub.sub!(id)

      assert subs_body =~ row.c_lowering,
             "subscriptions missing #{row.c_lowering} for #{id}"
    end
  end

  test "surface init lowers every contract cmd macro in generated init", %{out_dir: out_dir} do
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    init_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_init")

    for id <- @surface_cmd_ids do
      row = CmdSub.cmd!(id)

      present? =
        case id do
          # Value encode helper embeds COMPANION_SEND inside elmc_cmd_companion_send_value.
          :companion_send ->
            String.contains?(init_body, row.c_macro) or
              String.contains?(init_body, "elmc_cmd_companion_send_value")

          _ ->
            String.contains?(init_body, row.c_macro)
        end

      assert present?, "elmc_fn_Main_init missing #{row.c_macro} for #{id}"
    end
  end

  test "surface host init drains cmds whose kinds stay on the contract table", %{out_dir: out_dir} do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for surface cmd kind harness")

    harness_path = Path.join(out_dir, "c/surface_cmd_kinds_harness.c")
    expected_count = 40

    File.write!(
      harness_path,
      """
      #include <stdio.h>
      #include "elmc_pebble.h"
      #include "elmc_harness_helpers.h"

      static ElmcValue *surface_launch_context(void) {
        ElmcValue *screen_fields[4] = {
            elmc_harness_new_int(144), elmc_harness_new_int(168),
            elmc_harness_new_int(1), elmc_harness_new_int(2)};
        ElmcValue *screen = NULL;
        if (elmc_record_new_values(&screen, 4, screen_fields) != RC_SUCCESS) return NULL;
        for (int i = 0; i < 4; i++) elmc_release(screen_fields[i]);

        ElmcValue *ctx_fields[7] = {
            elmc_harness_new_int(2),
            elmc_harness_new_string(""),
            elmc_harness_new_string("gabbro"),
            screen,
            elmc_harness_new_bool(0),
            elmc_harness_new_bool(0),
            elmc_harness_new_bool(1)};
        ElmcValue *ctx = NULL;
        if (elmc_record_new_values(&ctx, 7, ctx_fields) != RC_SUCCESS) return NULL;
        for (int i = 0; i < 7; i++) {
          if (i != 3) elmc_release(ctx_fields[i]);
        }
        elmc_release(screen);
        return ctx;
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = surface_launch_context();
        if (!flags) return 2;
        if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 3;
        elmc_release(flags);

        int kinds[128];
        int count = 0;
        ElmcPebbleCmd cmd = {0};
        while (count < 128) {
          if (elmc_pebble_take_cmd(&app, &cmd) != 0) break;
          kinds[count++] = (int)cmd.kind;
        }

        elmc_pebble_deinit(&app);

        for (int i = 0; i < count; i++) {
          printf("%d\\n", kinds[i]);
        }
        printf("COUNT:%d\\n", count);
        return count >= #{expected_count} ? 0 : 4;
      }
      """
    )

    binary_path = Path.join(out_dir, "surface_cmd_kinds_harness")

    {compile_out, compile_code} =
      System.cmd(cc, host_link_args(out_dir, harness_path, binary_path))

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0, run_out

  kinds =
      run_out
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "COUNT:"))
      |> Enum.map(&String.to_integer/1)
      |> MapSet.new()

    contract_kinds =
      CmdSub.cmds()
      |> Enum.map(& &1.numeric)
      |> MapSet.new()

    assert Enum.all?(kinds, &MapSet.member?(contract_kinds, &1)),
           "host drained unknown cmd kind(s): #{inspect(Enum.reject(MapSet.to_list(kinds), &MapSet.member?(contract_kinds, &1)))}"

    assert MapSet.size(kinds) >= 40,
           "expected a broad init cmd drain, got #{MapSet.size(kinds)} unique kinds"
  end

  defp host_link_args(out_dir, harness_path, binary_path) do
    [
      "-std=c11",
      "-Wall",
      "-Wextra",
      "-include",
      Path.join(@support_dir, "elmc_host_stubs.h"),
      "-I#{@support_dir}",
      "-I#{Path.join(out_dir, "runtime")}",
      "-I#{Path.join(out_dir, "ports")}",
      "-I#{Path.join(out_dir, "c")}",
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_worker.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      harness_path,
      @harness_helpers_c,
      "-lm",
      "-o",
      binary_path
    ]
  end
end
