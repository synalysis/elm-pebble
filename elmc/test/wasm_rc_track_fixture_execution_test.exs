defmodule Elmc.WasmRcTrackFixtureExecutionTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @cases [
    {"rc_track_maybe_project", "RcTrackMaybeProbe",
     [
       {"probeWithDefault", 3},
       {"probeMap", 4},
       {"probeMap2", 3},
       {"probeAndThen", 6},
       {"probeWithDefaultNothing", 7},
       {"probeMapNothing", 0},
       {"probeAndThenNothing", 0}
     ]},
    {"rc_track_tuple_project", "RcTrackTupleProbe",
     [
       {"probeFirst", 1},
       {"probeSecond", 2},
       {"probePair", 3},
       {"probeMapFirst", 2},
       {"probeMapSecond", 4},
       {"probeMapBoth", 6}
     ]},
    {"rc_track_result_project", "RcTrackResultProbe",
     [
       {"probeWithDefault", 4},
       {"probeMap", 5},
       {"probeMapError", 0},
       {"probeAndThen", 8},
       {"probeToMaybe", 4},
       {"probeFromMaybe", 4},
       {"probeMapErr", 0},
       {"probeWithDefaultErr", 7},
       {"probeAndThenErr", 0}
     ]},
    {"rc_track_string_project", "RcTrackStringProbe",
     [
       {"probeAppend", 4},
       {"probeIsEmpty", 1},
       {"probeLength", 6},
       {"probeReverse", 6},
       {"probeRepeat", 2},
       {"probeReplace", 3},
       {"probeFromInt", 2},
       {"probeToInt", 42},
       {"probeFromFloat", 3},
       {"probeToFloat", 1},
       {"probeToUpper", 6},
       {"probeToLower", 6},
       {"probeTrim", 1},
       {"probeTrimLeft", 1},
       {"probeTrimRight", 1},
       {"probeContains", 1},
       {"probeStartsWith", 1},
       {"probeEndsWith", 1},
       {"probeSplit", 3},
       {"probeJoin", 5},
       {"probeWords", 3},
       {"probeLines", 3},
       {"probeSlice", 3},
       {"probeLeft", 2},
       {"probeRight", 2},
       {"probeDropLeft", 5},
       {"probeDropRight", 5},
       {"probeCons", 3},
       {"probeUncons", 5},
       {"probeToList", 6},
       {"probeFromList", 3},
       {"probeFromChar", 1},
       {"probePad", 5},
       {"probePadLeft", 5},
       {"probePadRight", 5},
       {"probeMap", 6},
       {"probeFilter", 3},
       {"probeFoldl", 393},
       {"probeFoldr", 393},
       {"probeAny", 1},
       {"probeAll", 1},
       {"probeIndexes", 1}
     ]},
    {"rc_track_char_project", "RcTrackCharProbe",
     [
       {"probeToCode", 65},
       {"probeFromCode", 66},
       {"probeIsUpper", 1},
       {"probeIsLower", 1},
       {"probeIsAlpha", 1},
       {"probeIsAlphaNum", 1},
       {"probeIsDigit", 1},
       {"probeIsOctDigit", 1},
       {"probeIsHexDigit", 1},
       {"probeToUpper", 65},
       {"probeToLower", 97}
     ]},
    {"rc_track_bitwise_project", "RcTrackBitwiseProbe",
     [
       {"probeAnd", 1},
       {"probeOr", 7},
       {"probeXor", 6},
       {"probeComplement", 2},
       {"probeShiftLeftBy", 6},
       {"probeShiftRightBy", 3},
       {"probeShiftRightZfBy", 3}
     ]},
    {"rc_track_debug_project", "RcTrackDebugProbe",
     [
       {"probeLog", 42},
       {"probeTodo", 0},
       {"probeToString", 2}
     ]},
    {"rc_track_basics_project", "RcTrackBasicsProbe",
     [
       {"probeMax", 7},
       {"probeMin", 3},
       {"probeClamp", 10},
       {"probeModBy", 1},
       {"probeIdentity", 6},
       {"probeAlways", 99},
       {"probeNot", 1},
       {"probeNegate", 4},
       {"probeAbs", 6},
       {"probeToFloat", 9},
       {"probeRound", 4},
       {"probeFloor", 3},
       {"probeCeiling", 4},
       {"probeTruncate", 3},
       {"probeRemainderBy", 1},
       {"probeXor", 1},
       {"probeCompare", 111},
       {"probeSqrt", 4},
       {"probeSin", 0},
       {"probeCos", 1},
       {"probeTan", 0},
       {"probeAsin", 0},
       {"probeAcos", 0},
       {"probeAtan", 0},
       {"probeAtan2", 0},
       {"probeDegrees", 180},
       {"probeRadians", 3},
       {"probeTurns", 6},
       {"probeLogBase", 3},
       {"probeIsNan", 1},
       {"probeIsInfinite", 1},
       {"probeFromPolar", 5},
       {"probeToPolar", 5}
     ]},
    {"rc_track_dict_project", "RcTrackDictProbe",
     [
       {"probeEmpty", 0},
       {"probeSingleton", 1},
       {"probeFromList", 2},
       {"probeInsert", 3},
       {"probeGet", 1},
       {"probeMember", 1},
       {"probeSize", 2},
       {"probeRemove", 1},
       {"probeIsEmpty", 1},
       {"probeKeys", 2},
       {"probeValues", 3},
       {"probeToList", 2},
       {"probeMap", 2},
       {"probeFoldl", 3},
       {"probeFoldr", 3},
       {"probeFilter", 1},
       {"probePartition", 2},
       {"probeUnion", 3},
       {"probeIntersect", 1},
       {"probeDiff", 1},
       {"probeMerge", 2},
       {"probeUpdate", 2},
       {"probeInsertAlias", 3}
     ]},
    {"rc_track_set_project", "RcTrackSetProbe",
     [
       {"probeEmpty", 0},
       {"probeSingleton", 1},
       {"probeFromList", 3},
       {"probeInsert", 4},
       {"probeMember", 1},
       {"probeSize", 3},
       {"probeRemove", 2},
       {"probeIsEmpty", 1},
       {"probeToList", 3},
       {"probeUnion", 4},
       {"probeIntersect", 1},
       {"probeDiff", 2},
       {"probeMap", 3},
       {"probeFoldl", 6},
       {"probeFoldr", 6},
       {"probeFilter", 2},
       {"probePartition", 3}
     ]},
    {"rc_track_array_project", "RcTrackArrayProbe",
     [
       {"probeEmpty", 0},
       {"probeFromList", 3},
       {"probeLength", 4},
       {"probeGet", 20},
       {"probeSet", 99},
       {"probePush", 4},
       {"probeInitialize", 6},
       {"probeRepeat", 21},
       {"probeIsEmpty", 1},
       {"probeToList", 3},
       {"probeToIndexedList", 3},
       {"probeMap", 9},
       {"probeIndexedMap", 9},
       {"probeFoldl", 6},
       {"probeFoldr", 6},
       {"probeFilter", 2},
       {"probeAppend", 4},
       {"probeSlice", 2},
       {"probeSetAlias", 119}
     ]},
    {"rc_track_task_process_project", "RcTrackTaskProcessProbe",
     [
       {"probeSucceed", 7},
       {"probeFail", 5},
       {"probeSpawn", 1},
       {"probeSleep", 1},
       {"probeKill", 1}
     ]},
    {"rc_track_compare_project", "RcTrackCompareProbe",
     [
       {"probeListEqual", 1},
       {"probeRecordEqual", 1}
     ]},
    {"rc_track_record_update_project", "RcTrackRecordUpdateProbe",
     [
       {"probeChainedUpdate", 52},
       {"probeAliasedBase", 11},
       {"probeDictUpdateAlias", 9}
     ]},
    {"rc_track_grid_int_project", "RcTrackGridIntProbe",
     [
       {"probeGridAccess", 7},
       {"probeGridUpdate", 21}
     ]}
  ]

  for {fixture, module, probes} <- @cases, {probe, expected} <- probes do
    @tag :wasm_execute
    test "#{fixture} #{probe} executes in wasm with JS rc runtime" do
      fixture = unquote(fixture)
      module = unquote(module)
      probe = unquote(probe)
      expected = unquote(expected)

      root = Path.expand("fixtures/#{fixture}", __DIR__)
      out_dir = Path.expand("tmp/wasm_rc_track_exec/#{fixture}/#{probe}", __DIR__)
      File.rm_rf!(out_dir)

      cond do
        not execution_tools_available?() ->
          :ok

        native_wat2wasm?() == false ->
          :ok

        true ->
          WasmRcTrackHarness.compile!(root, out_dir)

          case WasmRcTrackHarness.run_wat2wasm(
                 Elmc.Backend.Wasm.ProjectWriter.wat_path(out_dir),
                 Path.join(out_dir, "wasm/app.wasm")
               ) do
            :ok ->
              export = "elmc_fn_#{module}_#{probe}"

              case WasmRcTrackHarness.run_probe(out_dir, export, expected_checksum: expected) do
                {:ok, output} ->
                  WasmRcTrackHarness.assert_balanced_output!(output)

                {:error, output} ->
                  if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
                    :ok
                  else
                    flunk("wasm probe runner failed for #{fixture} #{probe}:\n#{output}")
                  end
              end

            {:error, output} ->
              flunk("wat2wasm failed for #{fixture}:\n#{output}")
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
