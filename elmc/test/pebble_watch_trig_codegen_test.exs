defmodule Elmc.PebbleWatchTrigCodegenTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    direct_render_only: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true,
    strip_dead_code: true,
    prod: true,
    codegen_profile: :size
  ]

  test "watchface_yes moon phase direct-render uses int trig lookups without soft-float cos" do
    out_dir = Path.join(System.tmp_dir!(), "yes-trig-out-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               "watchface_yes",
               Keyword.merge(@compile_opts, out_dir: out_dir, ir_cache: false)
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "drawMoonPhase_commands_append_native"
    assert generated =~ "cos_lookup"
    refute generated =~ "elmc_basics_cos"
    refute generated =~ "__adddf3"

    case Regex.run(~r/drawMoonPhase_commands_append_native[\s\S]*?ElmcValue \*owned\[(\d+)\]/, generated) do
      [_, slots] -> assert String.to_integer(slots) <= 16
      _ -> flunk("missing owned slot frame for moon append")
    end
  end
end
