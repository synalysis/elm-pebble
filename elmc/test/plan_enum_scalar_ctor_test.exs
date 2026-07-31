defmodule Elmc.PlanEnumScalarCtorTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.TestSupport.TemplateCompile

  test "all-nullary enum ctor lowers to const_int tag, not tuple2(tag, unit)" do
    Process.put(:elmc_constructor_tags, %{
      "Main.Left" => 1,
      "Main.Right" => 2,
      "Left" => 1,
      "Right" => 2
    })

    Process.put(:elmc_enum_ctors, MapSet.new(["Main.Left", "Main.Right", "Left", "Right"]))
    Process.put(:elmc_enum_types, MapSet.new(["Main.Direction", "Direction"]))

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Main", "Left"} => "",
      {"Main", "Right"} => ""
    })

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_enum_ctors)
      Process.delete(:elmc_enum_types)
      Process.delete(:elmc_union_constructor_payload_specs)
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_codegen_opts)
    end)

    decl = %{
      name: "pickLeft",
      args: [],
      type: "Direction",
      expr: %{op: :constructor_call, target: "Left", args: []}
    }

    decl_map = %{{"Main", "pickLeft"} => decl}
    Process.put(:elmc_program_decls, decl_map)

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    instrs = Enum.flat_map(plan.blocks, & &1.instrs)

    assert Enum.any?(instrs, fn
             %{op: :const_int, args: %{value: 1, union_ctor: ctor}} when is_binary(ctor) -> true
             _ -> false
           end),
           "expected scalar enum tag const_int"

    refute Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :unit}} -> true
             _ -> false
           end),
           "enum scalar must not emit unit payload"

    refute Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :tuple2}} -> true
             _ -> false
           end),
           "enum scalar must not wrap tag in tuple2"
  end

  test "mixed-union nullary ctor still builds tuple2(tag, unit)" do
    Process.put(:elmc_constructor_tags, %{
      "Main.Bar" => 1,
      "Main.Baz" => 2,
      "Bar" => 1,
      "Baz" => 2
    })

    # Foo = Bar | Baz Int — Bar is nullary but Foo is not an enum type.
    Process.put(:elmc_enum_ctors, MapSet.new())
    Process.put(:elmc_enum_types, MapSet.new())

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Main", "Bar"} => "",
      {"Main", "Baz"} => "Int"
    })

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_enum_ctors)
      Process.delete(:elmc_enum_types)
      Process.delete(:elmc_union_constructor_payload_specs)
      Process.delete(:elmc_program_decls)
    end)

    decl = %{
      name: "pickBar",
      args: [],
      type: "Foo",
      expr: %{op: :constructor_call, target: "Bar", args: []}
    }

    decl_map = %{{"Main", "pickBar"} => decl}

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    instrs = Enum.flat_map(plan.blocks, & &1.instrs)

    assert Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :unit}} -> true
             _ -> false
           end)

    assert Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :tuple2}} -> true
             _ -> false
           end)
  end

  test "game_2048 update passes direction macros to moveBoard_native without tuple peel" do
    alias Elmc.Test.CCodegenExtract

    out_dir = Path.expand("tmp/plan_enum_scalar_2048", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             TemplateCompile.compile_watch_template("game_2048",
               plan_ir_mode: :primary,
               plan_ir_strict: false,
               out_dir: out_dir
             )

    enum_ctors = Elmc.Backend.CCodegen.IRQueries.enum_constructor_set(result.ir)

    assert MapSet.member?(enum_ctors, "Main.Left") or MapSet.member?(enum_ctors, "Left")

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    update_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_update")

    assert update_body =~ "moveBoard_native"
    assert update_body =~ "ELMC_UNION_MAIN_LEFT" or update_body =~ "ELMC_UNION_MAIN_UP"

    # No Direction pack: unit + tuple2 before moveBoard.
    refute update_body =~
             ~r/elmc_unit\(\);\s*\n\s*Rc = elmc_tuple2\([^)]+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*Rc = elmc_fn_Main_moveBoard_native/s

    # No peel ternary on a packed Direction tuple at the call site.
    refute update_body =~ ~r/moveBoard_native\([^,]+,\s*\([^)]*ELMC_TAG_TUPLE2/

    # Identical direction arms share one moveBoard_native body.
    assert length(Regex.scan(~r/moveBoard_native/, update_body)) == 1

    # Stubs assign Direction macros into a native tag, then jump to the shared call.
    assert update_body =~ "ELMC_UNION_MAIN_LEFT"
    assert update_body =~ "ELMC_UNION_MAIN_RIGHT"
    refute update_body =~ ~r/elmc_new_int\(&owned\[\d+\],\s*[1-4]\);/
    refute update_body =~ "ELMC_TAG_TUPLE2"
  end
end
