defmodule Elmx.PartialConstructorEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "partial_constructor emits curried closure building tagged tuple" do
    expr = %{
      op: :partial_constructor,
      target: "GotListing",
      tag: 1,
      args: [%{op: :string_literal, value: "test_dir1"}],
      arity: 2
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :library)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "fn elmx_p1 ->"
    assert source =~ "{:GotListing, \"test_dir1\", elmx_p1}"
  end

  test "point-free partial_constructor top-level binding saturates synthetic parameter" do
    dir = Path.expand("../../elmc/test/fixtures/ts_derived_patterns_project", __DIR__)
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(dir)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)

    {:ok, modules} =
      Elmx.Backend.ElixirCodegen.emit_project(ir, %{
        entry_module: "Main",
        mode: :library,
        ir_sha256: "partial-constructor-test",
        user_module_names: ["TsDerivedPatterns", "Main"]
      })

    source = modules |> List.first() |> Map.fetch!(:source) |> IO.iodata_to_binary()

    assert source =~ "def elmx_fn_TsDerivedPatterns_constructorRefJust(elmx_p1)"
    assert source =~ "{:Just, elmx_p1}"
    refute source =~ "def elmx_fn_TsDerivedPatterns_constructorRefJust(_unused0)"
  end

  test "point-free function alias delegates with synthetic parameter" do
    dir = Path.expand("../../elmc/test/fixtures/rc_track_2048_project", __DIR__)
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(dir)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)

    {:ok, modules} =
      Elmx.Backend.ElixirCodegen.emit_project(ir, %{
        entry_module: "Main",
        mode: :library,
        ir_sha256: "fn-alias-test",
        user_module_names: ["RcTrack2048Probe", "Main"]
      })

    source = modules |> List.first() |> Map.fetch!(:source) |> IO.iodata_to_binary()

    assert source =~ "def elmx_fn_RcTrack2048Probe_reverseRows(elmx_p1)"
    refute source =~ "def elmx_fn_RcTrack2048Probe_reverseRows()"
  end
end
