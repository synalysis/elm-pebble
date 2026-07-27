defmodule Elmc.WasmRcTrackSmokeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @fixtures ~w(
    rc_track_basics_project rc_track_bitwise_project rc_track_list_project
    rc_track_maybe_project rc_track_result_project rc_track_string_project
    rc_track_char_project rc_track_tuple_project rc_track_dict_project
    rc_track_set_project rc_track_array_project rc_track_debug_project
    rc_track_task_process_project rc_track_compare_project
    rc_track_record_update_project rc_track_grid_int_project
    rc_track_2048_project
  )

  for fixture <- @fixtures do
    @tag :rc_track
    @tag :wasm_smoke
    test "wasm compile smoke for #{fixture}" do
      root = Path.expand("fixtures/#{unquote(fixture)}", __DIR__)
      out_dir = Path.expand("tmp/wasm_rc_track/#{unquote(fixture)}", __DIR__)
      File.rm_rf!(out_dir)

      assert {:ok, _} =
               Elmc.compile(root, %{
                 out_dir: out_dir,
                 entry_module: "Main",
                 strip_dead_code: false,
                 plan_ir_mode: :primary,
                 targets: [:wasm],
                 wasm_strict: false
               })

      wat_path = ProjectWriter.wat_path(out_dir)
      assert File.exists?(wat_path)
      wat = File.read!(wat_path)
      assert String.starts_with?(String.trim(wat), "(module")
      assert wat =~ "(result i32 i32)"

      runtime_c = Path.join(out_dir, "runtime/elmc_runtime.c")
      assert File.regular?(runtime_c)

      wat_path = ProjectWriter.wat_path(out_dir)

      if wat2wasm_available?() do
        wasm_path = Path.join(out_dir, "wasm/smoke.wasm")

        case WasmRcTrackHarness.run_wat2wasm(wat_path, wasm_path) do
          :ok ->
            case System.find_executable("wasm-validate") do
              nil -> :ok
              validator -> assert {_, 0} = System.cmd(validator, [wasm_path])
            end

          {:error, output} ->
            if wat2wasm_ulimit_oom?(output) do
              :ok
            else
              flunk("wat2wasm failed for #{unquote(fixture)}:\n#{output}")
            end
        end
      end
    end
  end

  defp wat2wasm_available? do
    System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil
  end

  defp wat2wasm_ulimit_oom?(output) when is_binary(output) do
    native_wat2wasm?() == false and output =~ "Out of memory"
  end

  defp native_wat2wasm? do
    System.find_executable("wat2wasm") != nil
  end
end
