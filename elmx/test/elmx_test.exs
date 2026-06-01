defmodule ElmxTest do
  use ExUnit.Case, async: false

  alias Elmx.CompileResult

  @fixture Path.expand("fixtures/minimal", __DIR__)
  @full_fixture Path.expand("fixtures/simple_project", __DIR__)

  test "compile_in_memory returns entry module without writing elixir sources" do
    tmp = System.tmp_dir!() |> Path.join("elmx-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(tmp) end)

    assert {:ok, %CompileResult{} = result} =
             Elmx.compile_in_memory(@fixture, %{entry_module: "Main", revision: "test-rev", strip_dead_code: true})

    assert is_atom(result.entry_module)
    assert function_exported?(result.entry_module, :debugger_execute, 1)
    refute File.exists?(Path.join(tmp, "elixir"))
  end

  test "compile writes elixir sources to out dir" do
    out = System.tmp_dir!() |> Path.join("elmx-out-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(out) end)

    assert {:ok, _} = Elmx.compile(@fixture, %{out_dir: out, strip_dead_code: true, entry_module: "Main"})
    assert File.exists?(Path.join(out, "elixir/elmx_manifest.json"))
  end
end
