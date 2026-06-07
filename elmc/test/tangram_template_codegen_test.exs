defmodule Elmc.TangramTemplateCodegenTest do
  use ExUnit.Case

  @repo_root Path.expand("../..", __DIR__)

  test "tangram watchface view codegen does not reference phantom Main.start helpers" do
    project_dir = scaffold_tangram_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-codegen-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated =~ "elmc_fn_Main_start",
           "expected minutePoint let-bindings to inline, not call phantom top-level helpers"

    assert generated =~ "ELMC_RENDER_OP_FILL_CIRCLE"
  end

  defp scaffold_tangram_project do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elmc-tangram-#{System.unique_integer([:positive])}"
      )

    template_src =
      Path.join(@repo_root, "ide/priv/project_templates/watchface_tangram_time")

    File.mkdir_p!(Path.join(tmp, "src"))
    File.mkdir_p!(Path.join(tmp, "protocol/src"))
    File.cp_r!(Path.join(template_src, "src"), Path.join(tmp, "src"))
    File.cp_r!(Path.join(template_src, "protocol/src"), Path.join(tmp, "protocol/src"))

    sources = [
      "src",
      "protocol/src",
      Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
      Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
      Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
      Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
    ]

    elm_json = %{
      "type" => "application",
      "source-directories" => sources,
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))
    tmp
  end
end
