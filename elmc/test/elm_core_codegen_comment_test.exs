defmodule Elmc.ElmCoreCodegenCommentTest do
  use ExUnit.Case

  alias Elmc.Backend.CCodegen.CallCompile

  @env %{"__module__" => "Main"}

  test "known elm/core qualified calls emit package comments" do
    expr = %{
      op: :qualified_call,
      target: "List.repeat",
      args: [%{op: :int_literal, value: 16}, %{op: :int_literal, value: 0}]
    }

    {code, _, _} = CallCompile.compile(expr, @env, 0)

    assert code =~ "/* elm/core: List.repeat */"
  end

  test "Basics qualified calls emit elm/core comments" do
    expr = %{
      op: :qualified_call,
      target: "Basics.max",
      args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
    }

    {code, _, _} = CallCompile.compile(expr, @env, 0)

    assert code =~ "/* elm/core: Basics.max */"
  end

  test "non elm/core qualified calls do not emit elm/core comments" do
    expr = %{op: :qualified_call, target: "Pebble.Cmd.none", args: []}

    {code, _, _} = CallCompile.compile(expr, @env, 0)

    refute code =~ "/* elm/core:"
  end

  test "compiled project generated C includes elm/core call comments" do
    project_dir = Path.expand("fixtures/rc_track_list_project", __DIR__)
    out_dir = Path.expand("tmp/elm_core_codegen_comments", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "/* elm/core: List.append */"
    refute generated_c =~ "/* elm/core: Pebble."
  end
end
