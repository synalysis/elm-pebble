defmodule Elmc.CAstLintTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Ast
  alias Elmc.Backend.C.Ast.{Emit, Lint}

  test "RC shell AST pretty-prints and lints" do
    ast =
      Ast.rc_fn(
        rc?: true,
        owned_decl: "ElmcValue *owned[1] = {0};",
        owned_count: 1,
        needs_catch: true,
        body: "Rc = elmc_new_int(out, 1);\nCHECK_RC(Rc);",
        epilogue: "elmc_release_array_lifo(owned, DIM(owned));"
      )

    assert :ok = Lint.run(ast)
    c = Emit.to_c(ast)
    assert c =~ "RC Rc = RC_SUCCESS;"
    assert c =~ "CATCH_BEGIN"
    assert c =~ "return Rc;"
  end

  test "lint rejects _take_value in RC body" do
    ast =
      Ast.rc_fn(
        rc?: true,
        needs_catch: true,
        body: "*out = elmc_new_int_take_value(1);"
      )

    assert {:error, issues} = Lint.run(ast)
    assert Enum.any?(issues, &match?({:error, :rc_take_shim, _}, &1))
  end

  test "run_source rejects early RC_ERR return" do
    source = """
    static RC elmc_fn_Main_bad(ElmcValue **out) {
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
      if (!out) return RC_ERR_INVALID_ARG;
      CATCH_END
      return Rc;
    }
    """

    assert {:error, issues} = Lint.run_source(source)
    assert Enum.any?(issues, &match?({:error, :early_rc_err_return, _}, &1))
  end
end
