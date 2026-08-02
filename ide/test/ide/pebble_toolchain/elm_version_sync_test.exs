defmodule Ide.PebbleToolchain.ElmVersionSyncTest do
  use ExUnit.Case, async: false

  alias Ide.Compiler
  alias Ide.PebbleToolchain.Command

  setup do
    previous = Application.get_env(:ide, :elm_compiler_version_override)
    on_exit(fn -> restore_override(previous) end)
    :ok
  end

  test "sync_project_elm_version rewrites application elm-version to compiler version" do
    Application.put_env(:ide, :elm_compiler_version_override, "0.19.2")

    dir =
      Path.join(
        System.tmp_dir!(),
        "elm_version_sync_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    elm_json_path = Path.join(dir, "elm.json")

    File.write!(
      elm_json_path,
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert :ok = Command.sync_project_elm_version(dir)
    assert Jason.decode!(File.read!(elm_json_path))["elm-version"] == "0.19.2"
  end

  test "protocol check syncs mismatched elm-version before elm make" do
    Application.put_env(:ide, :elm_compiler_version_override, nil)

    {:ok, installed} = Command.elm_compiler_version()
    mismatched = if installed == "0.19.1", do: "0.19.2", else: "0.19.1"

    workspace =
      Path.join(
        System.tmp_dir!(),
        "compiler_elm_version_check_#{System.unique_integer([:positive])}"
      )

    protocol_root = Path.join(workspace, "protocol")
    File.mkdir_p!(Path.join(protocol_root, "src/Companion"))
    on_exit(fn -> File.rm_rf(workspace) end)

    File.write!(
      Path.join(protocol_root, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => mismatched,
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(protocol_root, "src/Companion/Types.elm"),
      """
      module Companion.Types exposing (PhoneToWatch(..))

      type PhoneToWatch
          = Ready
      """
    )

    assert {:ok, %{status: :ok}} =
             Compiler.check_source_root(
               "protocol-elm-version-#{System.unique_integer([:positive])}",
               workspace_root: workspace,
               source_root: "protocol"
             )

    assert Jason.decode!(File.read!(Path.join(protocol_root, "elm.json")))["elm-version"] ==
             installed
  end

  defp restore_override(nil), do: Application.delete_env(:ide, :elm_compiler_version_override)
  defp restore_override(value), do: Application.put_env(:ide, :elm_compiler_version_override, value)
end
