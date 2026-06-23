defmodule Elmc.TestSupport.TangramTemplate do
  @moduledoc false

  @repo_root Path.expand("../../..", __DIR__)

  @spec scaffold_project() :: String.t()
  def scaffold_project do
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
