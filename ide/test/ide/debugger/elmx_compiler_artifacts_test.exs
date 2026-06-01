defmodule Ide.Debugger.ElmxCompilerArtifactsTest do
  use ExUnit.Case, async: false

  alias Ide.Compiler

  setup do
    old = Application.get_env(:ide, Ide.Debugger.RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, old)
    end)

    :ok
  end

  @tag :compiled_elixir
  test "build_elmx_artifacts_in_memory registers module when backend enabled" do
    Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, execution_backend: :compiled_elixir)

    project_dir = Path.expand("../../../../elmx/test/fixtures/minimal", __DIR__)
    revision = "elmx-test-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Compiler.build_elmx_artifacts_in_memory(project_dir, revision: revision)

    assert manifest["contract"] == "elmx.runtime_executor.v1"
    assert is_binary(manifest["generated_module"])
    assert Elmx.module_for_revision(revision)
  end
end
