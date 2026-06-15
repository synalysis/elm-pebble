defmodule Elmc.AllTemplatesCodegenTest do
  use ExUnit.Case

  @repo_root Path.expand("../..", __DIR__)

  @template_dirs Path.wildcard(Path.join(@repo_root, "ide/priv/project_templates/*"))
                 |> Enum.filter(&File.dir?/1)
                 |> Enum.map(&Path.basename/1)
                 |> Enum.sort()

  @tag timeout: 600_000
  test "every watch project template compiles to C" do
    failures =
      Enum.flat_map(@template_dirs, fn dir_name ->
        case compile_template(dir_name) do
          :ok -> []
          {:error, reason} -> [{dir_name, reason}]
        end
      end)

    if failures != [] do
      flunk("template C codegen failures:\n#{inspect(failures, limit: 20)}")
    end
  end

  defp compile_template(dir_name) do
    template_src = Path.join(@repo_root, "ide/priv/project_templates/#{dir_name}")
    tmp = Path.join(System.tmp_dir!(), "elmc-all-templates-#{dir_name}-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(Path.join(tmp, "src"))
      File.cp_r!(Path.join(template_src, "src"), Path.join(tmp, "src"))

      protocol_src = Path.join(template_src, "protocol/src")

      if File.dir?(protocol_src) do
        File.mkdir_p!(Path.join(tmp, "protocol/src"))
        File.cp_r!(protocol_src, Path.join(tmp, "protocol/src"))
      end

      sources =
        ["src"]
        |> maybe_add_protocol(protocol_src)
        |> Kernel.++([
          Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
          Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
          Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
          Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
        ])

      deps = %{
        "elm/core" => "1.0.5",
        "elm/json" => "1.1.3",
        "elm/time" => "1.0.0"
      }

      deps =
        if dir_name in ["game_jump_n_run", "watchface_poke_battle"],
          do: Map.put(deps, "elm/random", "1.0.0"),
          else: deps

      write_elm_json!(tmp, sources, deps)

      out_dir = Path.join(tmp, ".elmc-out")

      case Elmc.compile(tmp, %{out_dir: out_dir, entry_module: "Main", strip_dead_code: true}) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm_rf(tmp)
    end
  end

  defp maybe_add_protocol(sources, protocol_src) do
    if File.dir?(protocol_src), do: sources ++ ["protocol/src"], else: sources
  end

  defp write_elm_json!(tmpdir, sources, deps) do
    elm_json = %{
      "type" => "application",
      "source-directories" => sources,
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => deps,
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(tmpdir, "elm.json"), Jason.encode!(elm_json, pretty: true))
  end
end
