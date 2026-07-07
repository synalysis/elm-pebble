defmodule Elmc.IntIfChainTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.IfCompile
  alias Elmc.Backend.CCodegen.IntIfChain
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase

  defp int_eq(left, right) do
    %{op: :compare, kind: :eq, left: left, right: right}
  end

  defp union_literal(name) do
    %{
      op: :int_literal,
      value: 0,
      union_ctor: "Pebble.Platform." <> name
    }
  end

  test "parses or-of-int-equalities if into int case branches" do
    seconds = %{op: :var, name: "seconds"}

    or_cond =
      int_eq(seconds, %{op: :int_literal, value: 10})
      |> then(fn cond ->
        %{
          op: :if,
          cond: cond,
          then_expr: %{op: :constructor_call, target: "True", args: []},
          else_expr: %{
            op: :if,
            cond: int_eq(seconds, %{op: :int_literal, value: 30}),
            then_expr: %{op: :constructor_call, target: "True", args: []},
            else_expr: int_eq(seconds, %{op: :int_literal, value: 60})
          }
        }
      end)

    env =
      %{"seconds" => "seconds", __rc_catch__: true, __rc_required__: true}
      |> EnvBindings.put_native_int_binding("seconds", "seconds")

    assert {:ok, ^seconds, branches} =
             IntIfChain.parse_or_equality_if_chain(
               or_cond,
               seconds,
               %{op: :int_literal, value: 5},
               env
             )

    assert length(branches) == 4
    assert Enum.at(branches, -1).pattern == %{kind: :wildcard}
  end

  test "compiles or-of-int-equalities if as compact switch on native int subject" do
    seconds = %{op: :var, name: "seconds"}

    or_cond =
      int_eq(seconds, %{op: :int_literal, value: 10})
      |> then(fn cond ->
        %{
          op: :if,
          cond: cond,
          then_expr: %{op: :constructor_call, target: "True", args: []},
          else_expr: %{
            op: :if,
            cond: int_eq(seconds, %{op: :int_literal, value: 30}),
            then_expr: %{op: :constructor_call, target: "True", args: []},
            else_expr: int_eq(seconds, %{op: :int_literal, value: 60})
          }
        }
      end)

    env =
      %{"seconds" => "seconds", __rc_catch__: true, __rc_required__: true}
      |> EnvBindings.put_native_int_binding("seconds", "seconds")

    if_expr = %{
      op: :if,
      cond: or_cond,
      then_expr: seconds,
      else_expr: %{op: :int_literal, value: 5}
    }

    {code, out, _counter} = IfCompile.compile(if_expr, env, 0)

    assert is_binary(out)
    assert code =~ "switch (seconds)"
    assert code =~ "case 10:"
    assert code =~ "case 30:"
    assert code =~ "case 60:"
    assert code =~ "= seconds;"
    assert code =~ "default:"
    refute code =~ "native_bool_if_"
    refute code =~ "elmc_basics_compare"
  end

  test "parses chained native int equality if into int case branches" do
    tag = %{op: :var, name: "tag"}

    if_expr =
      int_eq(tag, %{op: :int_literal, value: 0})
      |> then(fn cond ->
        %{
          op: :if,
          cond: cond,
          then_expr: union_literal("LaunchSystem"),
          else_expr: %{
            op: :if,
            cond: int_eq(tag, %{op: :int_literal, value: 1}),
            then_expr: union_literal("LaunchUser"),
            else_expr: %{
              op: :if,
              cond: int_eq(tag, %{op: :int_literal, value: 2}),
              then_expr: union_literal("LaunchPhone"),
              else_expr: union_literal("LaunchUnknown")
            }
          }
        }
      end)

    env =
      %{"tag" => "tag", __rc_catch__: true, __rc_required__: true}
      |> EnvBindings.put_native_int_binding("tag", "tag")

    assert {:ok, ^tag, branches} =
             IntIfChain.parse_if_chain(
               if_expr.cond,
               if_expr.then_expr,
               if_expr.else_expr,
               env
             )

    assert length(branches) == 4
    assert Enum.at(branches, -1).pattern == %{kind: :wildcard}
  end

  test "compiles chained int equality if as switch on native int subject" do
    tag = %{op: :var, name: "tag"}

    branches = [
      %{pattern: %{kind: :int, value: 0}, expr: %{op: :int_literal, value: 10}},
      %{pattern: %{kind: :int, value: 1}, expr: %{op: :int_literal, value: 20}},
      %{pattern: %{kind: :int, value: 2}, expr: %{op: :int_literal, value: 30}},
      %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 99}}
    ]

    env =
      %{"tag" => "tag", __rc_catch__: true, __rc_required__: true}
      |> EnvBindings.put_native_int_binding("tag", "tag")

    if_expr = %{
      op: :if,
      cond: int_eq(tag, %{op: :int_literal, value: 0}),
      then_expr: Enum.at(branches, 0).expr,
      else_expr: %{
        op: :if,
        cond: int_eq(tag, %{op: :int_literal, value: 1}),
        then_expr: Enum.at(branches, 1).expr,
        else_expr: %{
          op: :if,
          cond: int_eq(tag, %{op: :int_literal, value: 2}),
          then_expr: Enum.at(branches, 2).expr,
          else_expr: Enum.at(branches, 3).expr
        }
      }
    }

    {code, out, _counter} = IfCompile.compile(if_expr, env, 0)

    assert out =~ "native_case_"
    assert code =~ "static const elmc_int_t native_lut_"
    refute code =~ "switch (tag)"
    refute code =~ "if ((tag == 0))"
    refute code =~ "elmc_new_int"
    assert code =~ "10"
    assert code =~ "99"
  end

  test "does not rewrite two-branch int if chains" do
    tag = %{op: :var, name: "tag"}

    if_expr = %{
      op: :if,
      cond: int_eq(tag, %{op: :int_literal, value: 0}),
      then_expr: %{op: :int_literal, value: 10},
      else_expr: %{op: :int_literal, value: 20}
    }

    env =
      %{"tag" => "tag", __rc_catch__: true, __rc_required__: true}
      |> EnvBindings.put_native_int_binding("tag", "tag")

    assert :error = IntIfChain.parse_if_chain(if_expr.cond, if_expr.then_expr, if_expr.else_expr, env)

    {code, _out, _counter} = IfCompile.compile(if_expr, env, 0)
    refute code =~ "switch (tag)"
    assert code =~ "if ((tag == 0))"
  end

  test "int case dispatch still handles explicit case expressions" do
    tag = %{op: :var, name: "tag"}

    branches = [
      %{pattern: %{kind: :int, value: 0}, expr: %{op: :int_literal, value: 10}},
      %{pattern: %{kind: :int, value: 1}, expr: %{op: :int_literal, value: 20}},
      %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 30}}
    ]

    env = %{"tag" => "tag"} |> EnvBindings.put_native_int_binding("tag", "tag")

    {code, _out, _counter} = CaseCompile.dispatch(tag, branches, env, 0)

    assert code =~ "static const elmc_int_t native_lut_"
    assert code =~ "native_case_"
    refute code =~ "switch (tag)"
    assert Regex.scan(~r/elmc_new_int/, code) |> length() == 1
  end

  test "dense int case on Pebble color constants uses static lookup table" do
    slot = %{op: :var, name: "slot"}
    color = fn name -> %{op: :qualified_call, target: "Pebble.Ui.Color." <> name, args: []} end

    branches = [
      %{pattern: %{kind: :int, value: 0}, expr: color.("vividCerulean")},
      %{pattern: %{kind: :int, value: 1}, expr: color.("pictonBlue")},
      %{pattern: %{kind: :int, value: 2}, expr: color.("tiffanyBlue")},
      %{pattern: %{kind: :int, value: 3}, expr: color.("cyan")},
      %{pattern: %{kind: :int, value: 4}, expr: color.("blueMoon")},
      %{pattern: %{kind: :int, value: 5}, expr: color.("electricBlue")},
      %{pattern: %{kind: :wildcard}, expr: color.("veryLightBlue")}
    ]

    env =
      %{"slot" => "slot", __rc_catch__: true, __rc_required__: true}
      |> EnvBindings.put_native_int_binding("slot", "slot")

    {code, out, _counter} = NativeIntCase.compile(slot, branches, env, 0)

    assert out == "owned[0]"
    assert code =~ "static const elmc_int_t native_lut_"
    assert code =~ "ELMC_COLOR_VIVID_CERULEAN"
    assert code =~ "ELMC_COLOR_VERY_LIGHT_BLUE"
    refute code =~ "switch (slot)"
    assert Regex.scan(~r/elmc_new_int/, code) |> length() == 1
  end
end
