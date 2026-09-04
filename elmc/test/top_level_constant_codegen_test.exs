defmodule Elmc.TopLevelConstantCodegenTest do
  use ExUnit.Case

  alias Elmc.TestSupport.CachedCompile

  @moduletag timeout: 300_000
  @repo_root Path.expand("../..", __DIR__)

  test "top-level constants referenced in add_const call the value function" do
    project_dir = Path.expand("tmp/top_level_constant_project", __DIR__)
    out_dir = Path.expand("tmp/top_level_constant_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))

    template_dir = Path.join(@repo_root, "ide/priv/project_templates/watch_demo_drawing_showcase")

    File.cp!(
      Path.join(template_dir, "src/Main.elm"),
      Path.join(project_dir, "src/Main.elm")
    )

    File.cp_r!(Path.join(template_dir, "resources"), Path.join(project_dir, "resources"))

    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(%{
      "type" => "application",
      "source-directories" => [
        "src",
        Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
        Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
        Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
        Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
      ],
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
    }))

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               plan_ir_mode: :primary,
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ ~r/elmc_as_int\(contentTop\)/
    assert generated_c =~ "static elmc_int_t elmc_fn_Main_contentTop(ElmcValue *model"
    assert generated_c =~ "elmc_fn_Main_contentTop("
    assert generated_c =~ "path_point_count = 3"
    assert generated_c =~ "ELMC_RENDER_OP_PATH_FILLED"
  end
end
