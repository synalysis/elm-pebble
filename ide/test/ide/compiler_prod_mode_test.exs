defmodule Ide.CompilerProdModeTest do
  use ExUnit.Case, async: true

  alias Ide.Compiler

  test "build_page_compile_opts enables prod with warn policy" do
    opts =
      Compiler.build_page_compile_opts(
        workspace_root: "/tmp/demo",
        source_roots: ["watch"]
      )

    assert Keyword.get(opts, :prod) == true
    assert Keyword.get(opts, :debug_usage_policy) == :warn
  end

  test "production_compile_opts enables prod with error policy" do
    opts = Compiler.production_compile_opts(workspace_root: "/tmp/demo")

    assert Keyword.get(opts, :prod) == true
    assert Keyword.get(opts, :debug_usage_policy) == :error
  end
end
