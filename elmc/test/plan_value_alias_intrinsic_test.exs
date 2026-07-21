defmodule Elmc.PlanValueAliasIntrinsicTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Native.FunctionCall
  alias Elmc.Backend.Plan.Lower.{Call, Function, Intrinsics}

  test "String.fromInt value alias lowers to unary runtime from_int, not zero-arg call" do
    decl = %{
      name: "fromInt",
      args: [],
      type: "Int -> String",
      expr: %{op: :qualified_call, target: "Elm.Kernel.String.fromNumber", args: []}
    }

    assert {:ok, plan} =
             Intrinsics.try_lower(decl, "String", %{}, rc_required: true, web: true, targets: [:wasm])

    assert length(plan.params) == 1
    assert hd(plan.params).name =~ "__"

    ops = for b <- plan.blocks, i <- b.instrs, do: {i.op, i.args}
    refute Enum.any?(ops, fn {:call_fn, %{args: []}} -> true; _ -> false end)

    assert Enum.any?(ops, fn
             {:call_runtime, %{builtin: :string_from_int_value}} -> true
             {:call_runtime, %{builtin: :string_from_float}} -> true
             _ -> false
           end)
  end

  test "Basics.gt value alias forwards typed arity instead of zero-arg call_fn" do
    decl = %{
      name: "gt",
      args: [],
      type: "comparable -> comparable -> Bool",
      expr: %{op: :qualified_call, target: "Elm.Kernel.Utils.gt", args: []}
    }

    assert {:ok, plan} =
             Function.lower(decl, "Basics", %{}, rc_required: true, web: true, targets: [:wasm])

    assert length(plan.params) == 2

    ops = for b <- plan.blocks, i <- b.instrs, do: {i.op, i.args}

    refute Enum.any?(ops, fn
             {:call_fn, %{module: _, name: _, args: []}} -> true
             _ -> false
           end)
  end

  test "Basics.pow kernel alias lowers to runtime pow without call_rewrite loop" do
    decl = %{
      name: "pow",
      args: [],
      type: "number -> number -> number",
      expr: %{op: :qualified_call, target: "Elm.Kernel.Basics.pow", args: []}
    }

    assert {:ok, plan} =
             Function.lower(decl, "Basics", %{}, rc_required: false, web: true, targets: [:wasm])

    assert length(plan.params) == 2

    ops = for b <- plan.blocks, i <- b.instrs, do: {i.op, i.args}

    assert Enum.any?(ops, fn
             {:call_runtime, %{builtin: :basics_pow}} -> true
             _ -> false
           end)
  end

  test "effective_decl_args uses type arity when Kernel callee is missing" do
    decl = %{
      name: "slice",
      args: [],
      type: "Int -> Int -> String -> String",
      expr: %{op: :qualified_call, target: "Elm.Kernel.String.slice", args: []}
    }

    assert length(FunctionEmit.effective_decl_args(decl, "String", %{})) == 3
  end

  test "call_site_arg_kinds uses type arity for Kernel aliases with empty IR args" do
    decl = %{
      name: "unsafeGet",
      args: [],
      type: "Int -> JsArray a -> a",
      expr: %{op: :qualified_call, target: "Elm.Kernel.JsArray.unsafeGet", args: []}
    }

    assert FunctionCall.call_site_arg_kinds(decl, "Elm.JsArray", %{}) == [:native_int, :boxed]
  end

  test "call_site_arg_kinds stays empty for lambda/thunk alias bodies" do
    decl = %{
      name: "chopForwardSlashes",
      args: [],
      type: "String -> String",
      expr: %{
        op: :lambda,
        args: ["__compose_arg__"],
        body: %{op: :var, name: "__compose_arg__"}
      }
    }

    assert FunctionCall.call_site_arg_kinds(decl, "Pages.Internal.String", %{}) == []
  end

  test "effective_decl_args ignores type arity for lambda/thunk bodies" do
    decl = %{
      name: "chopForwardSlashes",
      args: [],
      type: "String -> String",
      expr: %{
        op: :lambda,
        args: ["__compose_arg__"],
        body: %{op: :var, name: "__compose_arg__"}
      }
    }

    assert FunctionEmit.effective_decl_args(decl, "Pages.Internal.String", %{}) == []
  end

  test "top-level var ref to List.cons becomes a closure, not a zero-arg call_fn" do
    alias Elmc.Backend.Plan.{Builder, Context}

    cons = %{
      name: "cons",
      args: [],
      type: "a -> List a -> List a",
      expr: %{op: :qualified_call, target: "Elm.Kernel.List.cons", args: []}
    }

    decl_map = %{{"List", "cons"} => cons}

    ctx =
      Context.new(
        module: "List",
        function_name: "reverse",
        decl_map: decl_map,
        params: ["list"],
        rc_required: true,
        fallible: true,
        function_tail: false
      )

    b = Builder.new("List", "reverse", args: ["list"], rc_required: true, fallible: true)

    assert {:ok, _reg, b1} = Call.compile_top_level_ref("cons", ctx, b)
    instrs = b1.current_block.instrs ++ Enum.flat_map(b1.blocks, & &1.instrs)
    assert Enum.any?(instrs, &(&1.op == :make_closure))
    refute Enum.any?(instrs, fn
             %{op: :call_fn, args: %{name: "cons", args: []}} -> true
             _ -> false
           end)
  end


  test "under-applied String.slice call site curries instead of zero-arg call_fn" do
    alias Elmc.Backend.Plan.{Builder, Context}

    slice = %{
      name: "slice",
      args: [],
      type: "Int -> Int -> String -> String",
      expr: %{op: :qualified_call, target: "Elm.Kernel.String.slice", args: []}
    }

    decl_map = %{{"String", "slice"} => slice}

    ctx =
      Context.new(
        module: "Main",
        function_name: "use",
        decl_map: decl_map,
        params: [],
        rc_required: true,
        fallible: true,
        function_tail: false
      )

    b = Builder.new("Main", "use", args: [], rc_required: true, fallible: true)

    assert {:ok, _reg, b1} =
             Call.compile_call(
               %{
                 op: :qualified_call,
                 target: "String.slice",
                 args: [%{op: :int_literal, value: 1}]
               },
               ctx,
               b
             )

    instrs = b1.current_block.instrs ++ Enum.flat_map(b1.blocks, & &1.instrs)
    ops = Enum.map(instrs, & &1.op)
    assert :make_closure in ops

    refute Enum.any?(instrs, fn
             %{op: :call_fn, args: %{name: "slice", args: args}} -> length(List.wrap(args)) < 3
             %{op: :call_fn, args: %{module: "Elm.Kernel.String", name: "slice"}} -> true
             _ -> false
           end)
  end
end



