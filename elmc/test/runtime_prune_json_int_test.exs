defmodule Elmc.RuntimePruneJsonIntTest do
  use ExUnit.Case, async: false

  @smoke_screen_main Path.expand("../../ide/priv/project_templates/watchface_smoke_screen/src/Main.elm", __DIR__)

  test "int-only json runtime disables float number parsing and omits float helpers" do
    out_dir = Path.expand("tmp/runtime_prune_json_int_out", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    RC uses_json_int_decode(ElmcValue **out, ElmcValue *json) {
      ElmcValue *decoder = elmc_json_decode_int_decoder();
      ElmcValue *result = elmc_json_decode_string(decoder, json);
      elmc_release(decoder);
      if (!result) return RC_ERR_INVALID_ARG;
      *out = result;
      return RC_SUCCESS;
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
    header = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))

    assert runtime =~ "#define ELMC_JSON_FLOAT_NUMBERS 0"
    refute runtime =~ ~r/RC elmc_new_float\(/
    refute runtime =~ "elmc_new_float_take"
    refute header =~ "elmc_new_float_take"
    refute header =~ "elmc_json_decode_float_decoder"
    refute header =~ "RC elmc_new_float("
  end

  test "smoke-screen watchface prunes json runtime without float helpers" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/runtime_prune_smoke_screen_project", __DIR__)
    out_dir = Path.expand("tmp/runtime_prune_smoke_screen_out", __DIR__)

    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@smoke_screen_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_runtime: true,
               pebble_int32: true
             })

    runtime = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))
    header = File.read!(Path.join(out_dir, "runtime/elmc_runtime.h"))
    pebble_header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    assert pebble_header =~ "#define ELMC_PEBBLE_FEATURE_COMPACT_DRAW 1"
    assert runtime =~ "#define ELMC_JSON_FLOAT_NUMBERS 0"
    refute runtime =~ ~r/RC elmc_new_float\(/
    refute runtime =~ "elmc_new_float_take"
    refute header =~ "elmc_new_float_take"
    refute header =~ "elmc_json_decode_float_decoder"
    refute header =~ "RC elmc_new_float("
    assert runtime =~ "(void)value;"
    refute runtime =~ "(double)elmc_as_int"
  end
end
