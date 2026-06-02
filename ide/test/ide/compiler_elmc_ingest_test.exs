defmodule Ide.CompilerElmcIngestTest do
  use ExUnit.Case, async: true

  alias Ide.Compiler
  alias Ide.Debugger.Types.{CompileIngestBridge, ElmcCliIngestBridge}

  test "compiler check and CLI bridge agree on attrs shape" do
    dir = tmp_project!()

    cli_attrs =
      dir
      |> Elmc.CLI.check_project()
      |> ElmcCliIngestBridge.from_check_run(checked_path: dir)

    assert {:ok, compiler_result} =
             Compiler.check("elmc-ingest-#{System.unique_integer([:positive])}",
               workspace_root: dir
             )

    bridge_attrs = CompileIngestBridge.from_compiler_check_result(compiler_result)

    assert cli_attrs.status == bridge_attrs.status
    assert cli_attrs.checked_path == bridge_attrs.checked_path
    assert cli_attrs.error_count == bridge_attrs.error_count
    assert cli_attrs.warning_count == bridge_attrs.warning_count
  end

  defp tmp_project! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "compiler_elmc_ingest_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(dir, "src"))

    File.write!(
      Path.join(dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{"direct" => %{}, "indirect" => %{}},
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(Path.join(dir, "src/Main.elm"), "module Main exposing (..)\n")
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
