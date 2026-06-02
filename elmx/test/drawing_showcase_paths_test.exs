defmodule Elmx.DrawingShowcasePathsTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../..", __DIR__)
  @template_main Path.join([
                   @repo_root,
                   "ide/priv/project_templates/watch_demo_drawing_showcase/src/Main.elm"
                 ])

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elmx-drawing-showcase-#{System.unique_integer([:positive])}"
      )

    src = Path.join(tmp, "src")
    File.mkdir_p!(src)
    File.cp!(@template_main, Path.join(src, "Main.elm"))

    elm_json = %{
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
    }

    File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))
    on_exit(fn -> File.rm_rf(tmp) end)
    %{project_dir: tmp}
  end

  @tag timeout: 120_000
  test "Paths page view_output includes path drawables after DownPressed", %{project_dir: dir} do
    revision = "drawing-paths-#{System.unique_integer([:positive])}"

    assert {:ok, %Elmx.CompileResult{} = result} =
             Elmx.compile_in_memory(dir, %{
               entry_module: "Main",
               revision: revision,
               strip_dead_code: true
             })

    lc = %{
      "screen" => %{
        "width" => 144,
        "height" => 168,
        "shape" => "Rectangular",
        "color_mode" => "BlackWhite"
      }
    }

    assert {:ok, init} =
             Elmx.Runtime.Executor.execute_generated(result.entry_module, %{
               "current_model" => %{"launch_context" => lc},
               "message" => nil
             })

    rm =
      get_in(init, [:model_patch, "runtime_model"]) ||
        get_in(init, ["model_patch", "runtime_model"])

    assert {:ok, step} =
             Elmx.Runtime.Executor.execute_generated(result.entry_module, %{
               "current_model" => %{"launch_context" => lc, "runtime_model" => rm},
               "message" => "DownPressed"
             })

    patch = step[:model_patch] || step["model_patch"]
    runtime_model = patch["runtime_model"] || patch[:runtime_model]
    assert runtime_model["pageIndex"] == 1

    view_output = step[:view_output] || step["view_output"]

    kinds =
      view_output
      |> Enum.map(&(&1["kind"] || &1[:kind]))

    assert "path_filled" in kinds
    assert "path_outline" in kinds
    assert "path_outline_open" in kinds
  end
end
