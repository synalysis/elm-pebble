defmodule Elmc.AllTemplatesCodegenTest do
  use ExUnit.Case

  @moduletag :slow

  alias Elmc.TestSupport.TemplateCompile

  @repo_root Path.expand("../..", __DIR__)

  @template_dirs Path.wildcard(Path.join(@repo_root, "ide/priv/project_templates/*"))
                 |> Enum.filter(&File.dir?/1)
                 |> Enum.map(&Path.basename/1)
                 |> Enum.sort()

  @tag timeout: 1_200_000
  test "every watch project template compiles to C" do
    failures =
      Enum.flat_map(@template_dirs, fn dir_name ->
        case TemplateCompile.compile_watch_template(dir_name, strip_dead_code: true) do
          {:ok, _} -> []
          {:error, reason} -> [{dir_name, reason}]
        end
      end)

    if failures != [] do
      flunk("template C codegen failures:\n#{inspect(failures, limit: 20)}")
    end
  end
end
