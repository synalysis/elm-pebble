defmodule Elmx.LoaderContractTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Loader

  test "compile_module returns compile_failure_detail on syntax error" do
    mod = %{
      name: "BadModule",
      source: "defmodule BadModule do\n  def foo do\n    1 +\n  end\nend\n",
      virtual_path: "bad.ex"
    }

    assert {:error, {:compile_failed, "BadModule", detail}} = Loader.compile_module(mod)
    assert is_map(detail)
    assert is_binary(detail.message) or is_list(detail)
  end

  test "compile_module loads valid generated source" do
    mod = %{
      name: "LoaderTestMod",
      source: "defmodule LoaderTestMod do\ndef hello, do: :ok\nend",
      virtual_path: "loader_test.ex"
    }

    assert {:ok, %{module: loaded}} = Loader.compile_module(mod)
    assert loaded == LoaderTestMod
    assert apply(loaded, :hello, []) == :ok
    :ok = Loader.purge(loaded)
  end
end
