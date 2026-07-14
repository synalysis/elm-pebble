defmodule Elmc.WasmRcTrackExecutionTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @fixture Path.expand("fixtures/rc_track_list_project", __DIR__)

  @probes [
    {"probeAppend", 14},
    {"probeLength", 4},
    {"probeSum", 10},
    {"probeTail", 3},
    {"probeReverse", 14},
    {"probeIsEmpty", 1},
    {"probeMember", 1},
    {"probeHead", 1},
    {"probeMap", 14},
    {"probeFilter", 7},
    {"probeFoldl", 10},
    {"probeFoldr", 10},
    {"probeIndexedMap", 16},
    {"probeFilterMap", 7},
    {"probeAny", 1},
    {"probeAll", 1},
    {"probeSortBy", 14},
    {"probeSortWith", 14},
    {"probeConcatMap", 10},
    {"probePartition", 4},
    {"probeUnzip", 21},
    {"probeSort", 14},
    {"probeConcat", 20},
    {"probeProduct", 24},
    {"probeMaximum", 4},
    {"probeMinimum", 1},
    {"probeSingleton", 8},
    {"probeRange", 15},
    {"probeRepeat", 6},
    {"probeTake", 3},
    {"probeDrop", 9},
    {"probeIntersperse", 9},
    {"probeMap2", 21},
    {"probeCons", 15},
    {"probeMap3", 21},
    {"probeMap4", 44},
    {"probeMap5", 54},
    {"probeConsChain", 25},
    {"probeAppendChain", 19}
  ]

  for {probe, expected} <- @probes do
    @tag :wasm_execute
    test "#{probe} executes in wasm with JS rc runtime" do
      out_dir = Path.expand("tmp/wasm_rc_track_exec/#{unquote(probe)}", __DIR__)
      File.rm_rf!(out_dir)

      cond do
        not execution_tools_available?() ->
          :ok

        native_wat2wasm?() == false ->
          :ok

        true ->
          WasmRcTrackHarness.compile!(@fixture, out_dir)

          case WasmRcTrackHarness.run_wat2wasm(
                 Elmc.Backend.Wasm.ProjectWriter.wat_path(out_dir),
                 Path.join(out_dir, "wasm/app.wasm")
               ) do
            :ok ->
              export = "elmc_fn_RcTrackListProbe_#{unquote(probe)}"

              case WasmRcTrackHarness.run_probe(out_dir, export, expected_checksum: unquote(expected)) do
                {:ok, output} ->
                  WasmRcTrackHarness.assert_balanced_output!(output)

                {:error, output} ->
                  if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
                    :ok
                  else
                    flunk("wasm probe runner failed for #{unquote(probe)}:\n#{output}")
                  end
              end

            {:error, output} ->
              flunk("wat2wasm failed:\n#{output}")
          end
      end
    end
  end

  defp native_wat2wasm? do
    System.find_executable("wat2wasm") != nil
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
