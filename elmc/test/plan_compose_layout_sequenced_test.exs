defmodule Elmc.PlanComposeLayoutSequencedTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  alias Elmc.Backend.CCodegen.{IRQueries, VarAnalysis}
  alias Elmc.Backend.Plan.Lower.Function

  @wiring_fixture Path.expand("fixtures/wasm_web_wiring_diagram_project", __DIR__)

  defp sequenced_branch(ir) do
    mod = Enum.find(ir.modules, &(&1.name == "Internal.Cartesian.Layout"))
    decl = Enum.find(mod.declarations, &(&1.name == "composeLayout"))

    sequenced =
      decl.expr.branches
      |> Enum.find(&(&1.pattern.name == "C.Sequenced"))

    {mod, decl, sequenced}
  end

  defp collect_let_bindings(expr) do
    do_collect_let_bindings([], expr)
  end

  defp do_collect_let_bindings(acc, %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    do_collect_let_bindings(acc ++ [{name, value_expr}], in_expr)
  end

  defp do_collect_let_bindings(acc, tail), do: {acc, tail}

  defp bound_vars_in_pattern(pattern, acc) do
    case pattern do
      %{kind: :var, name: name} ->
        MapSet.put(acc, name)

      %{kind: :tuple, elements: elements} when is_list(elements) ->
        Enum.reduce(elements, acc, &bound_vars_in_pattern/2)

      %{kind: :constructor, bind: bind, arg_pattern: arg_pattern} ->
        acc1 = if is_binary(bind), do: MapSet.put(acc, bind), else: acc

        if is_map(arg_pattern) do
          bound_vars_in_pattern(arg_pattern, acc1)
        else
          acc1
        end

      _ ->
        acc
    end
  end

  test "Sequenced let/caseSubject does not treat case arm locals as inner pattern vars" do
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(@wiring_fixture)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    {_mod, _decl, sequenced} = sequenced_branch(ir)

    {bindings, tail} = collect_let_bindings(sequenced.expr)
    pattern = hd(tail.branches).pattern
    pattern_vars = bound_vars_in_pattern(pattern, MapSet.new())

    refute MapSet.member?(pattern_vars, "l")
    refute MapSet.member?(pattern_vars, "r")

    bind_idx = Enum.find_index(bindings, fn {name, _} -> name == "caseSubject" end)

    deferred =
      bindings
      |> Enum.with_index()
      |> Enum.filter(fn {{_name, value}, idx} ->
        idx != bind_idx and
          MapSet.intersection(VarAnalysis.used_vars(value), pattern_vars) |> MapSet.size() > 0
      end)
      |> Enum.map(fn {{name, _}, _} -> name end)

    assert "pair" not in deferred
    assert deferred == []
  end

  test "composeLayout lowers after dependency constructor tags are available" do
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(@wiring_fixture)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    {mod, decl, _sequenced} = sequenced_branch(ir)

    decl_map = IRQueries.function_decl_map(ir)
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_program_decls, decl_map)
    Process.delete(:elmc_plan_unsupported_reasons)

    fd = %{name: decl.name, args: decl.args, expr: decl.expr}

    assert {:ok, _plan} = Function.lower(fd, mod.name, decl_map, rc_required: false)
  end

  test "boundOf reads Layout.extent at alphabetical field index 1" do
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(@wiring_fixture)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    mod = Enum.find(ir.modules, &(&1.name == "Internal.Cartesian.Layout"))
    decl = Enum.find(mod.declarations, &(&1.name == "boundOf"))
    decl_map = IRQueries.function_decl_map(ir)

    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
    Process.put(:elmc_union_constructor_payload_specs, IRQueries.union_constructor_payload_specs_map(ir))
    Process.delete(:elmc_plan_unsupported_reasons)

    on_exit(fn ->
      Process.delete(:elmc_union_constructor_payload_specs)
      Process.delete(:elmc_inline_record_literal_shapes)
      Process.delete(:elmc_record_alias_shapes)
    end)

    fd = %{name: decl.name, args: decl.args, expr: decl.expr}

    assert {:ok, plan} = Function.lower(fd, mod.name, decl_map, rc_required: false)

    layout_extent_gets =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(fn instr ->
        instr.op == :record_get and Map.get(instr.args, :field) == "extent"
      end)

    assert layout_extent_gets != []

    indices =
      layout_extent_gets
      |> Enum.map(& &1.args[:field_index])
      |> Enum.map(fn
        idx when is_binary(idx) ->
          case Integer.parse(idx) do
            {n, _} -> n
            :error -> nil
          end

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    # Layout payload (alpha): extent at 1; Leaf payload (alpha): extent at 0.
    assert indices == [0, 1] or indices == [1],
           "expected Layout/Leaf alphabetical extent indices, got #{inspect(indices)}"
  end

  test "layout dispatches nested Composed patterns when outer C tag is shared" do
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(@wiring_fixture)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    mod = Enum.find(ir.modules, &(&1.name == "Internal.Cartesian.Layout"))
    decl = Enum.find(mod.declarations, &(&1.name == "layout"))
    decl_map = IRQueries.function_decl_map(ir)

    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
    Process.put(:elmc_union_constructor_payload_specs, IRQueries.union_constructor_payload_specs_map(ir))
    Process.delete(:elmc_plan_unsupported_reasons)

    on_exit(fn ->
      Process.delete(:elmc_union_constructor_payload_specs)
      Process.delete(:elmc_inline_record_literal_shapes)
      Process.delete(:elmc_record_alias_shapes)
    end)

    fd = %{name: decl.name, args: decl.args, expr: decl.expr}

    assert {:ok, plan} = Function.lower(fd, mod.name, decl_map, rc_required: false)

    instrs = plan.blocks |> Enum.flat_map(& &1.instrs)

    compose_calls =
      Enum.filter(instrs, fn
        %{op: :call_fn, args: %{module: "Internal.Cartesian.Layout", name: "composeLayout"}} -> true
        _ -> false
      end)

    ctor_tag_tests = Enum.count(instrs, &(&1.op == :test_ctor_tag))

    br_if_blocks =
      Enum.count(plan.blocks, fn block ->
        match?({:br_if, _, _, _}, block.terminator)
      end)

    assert compose_calls != [],
           "expected layout to delegate composed branches to composeLayout"

    assert ctor_tag_tests >= 2,
           "expected nested constructor-tag dispatch for shared outer C tags, got #{ctor_tag_tests} test_ctor_tag ops"

    assert br_if_blocks >= 2,
           "expected br_if case dispatch inside layout, got #{br_if_blocks} br_if blocks"
  end
end
