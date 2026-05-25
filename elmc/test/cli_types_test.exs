defmodule Elmc.CLI.TypesTest do
  use ExUnit.Case, async: true

  alias Elmc.CLI

  test "check_project returns project_run shape" do
    with_tmp_project(fn dir ->
      result = CLI.check_project(dir)

      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :output)
      assert Map.has_key?(result, :warnings)
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_list(result.warnings)
    end)
  end

  defp with_tmp_project(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "elmc_cli_types_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(dir, "src"))
    File.write!(Path.join(dir, "src/Main.elm"), "module Main exposing (..)\n")

    on_exit(fn -> File.rm_rf(dir) end)
    fun.(dir)
  end
end
