defmodule Ide.Debugger.CompiledElixirExecuteTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.RuntimeExecutor.CompiledElixirAdapter

  setup do
    old = Application.get_env(:ide, Ide.Debugger.RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, old)
    end)

    Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, execution_backend: :compiled_elixir)
    _ = Application.ensure_all_started(:elmx)
    :ok
  end

  test "adapter executes in-memory compiled simple_project Main" do
    project_dir = Path.expand("../../../../elmx/test/fixtures/simple_project", __DIR__)
    revision = "ide-elmx-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(project_dir, revision: revision)

    assert manifest["contract"] == "elmx.runtime_executor.v1"

    request = %{
      elmx_manifest: manifest,
      elmx_revision: revision,
      current_model: %{"launch_context" => %{}},
      message: nil
    }

    assert {:ok, payload} = CompiledElixirAdapter.execute(request)
    assert get_in(payload.model_patch, ["runtime_model", "value"]) != nil
    assert payload.runtime["execution_backend"] == "compiled_elixir" or
             get_in(payload.runtime, [:execution_backend]) == "compiled_elixir"
  end
end
