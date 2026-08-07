defmodule Elmc.NullaryConstructorCallEmitTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CallCompile
  alias Elmc.Backend.CCodegen.DirectRender.Emit.ExprDispatch

  setup do
    Process.put(:elmc_constructor_tags, %{
      "Companion.Types.Black" => 1,
      "Companion.Types.White" => 2,
      "Black" => 1,
      "White" => 2,
      "Main.Bar" => 1,
      "Bar" => 1
    })

    Process.put(
      :elmc_enum_ctors,
      MapSet.new(["Companion.Types.Black", "Companion.Types.White", "Black", "White"])
    )

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_enum_ctors)
    end)

    :ok
  end

  test "nullary enum constructor_call emits boxed tag int, not elmc_fn_*" do
    {code, _var, _counter} =
      CallCompile.compile(
        %{op: :constructor_call, target: "Companion.Types.Black", args: []},
        %{},
        0
      )

    assert code =~ "elmc_new_int"
    refute code =~ "elmc_fn_Companion_Types_Black"
  end

  test "nullary enum constructor_ref emits boxed tag int via ExprDispatch" do
    {code, _var, _counter} =
      ExprDispatch.compile(%{op: :constructor_ref, target: "Companion.Types.White"}, %{}, 0)

    assert code =~ "elmc_new_int"
    refute code =~ "elmc_fn_Companion_Types_White"
  end

  test "mixed-union nullary constructor_call emits tuple2(tag, unit)" do
    {code, _var, _counter} =
      CallCompile.compile(%{op: :constructor_call, target: "Main.Bar", args: []}, %{}, 0)

    assert code =~ "elmc_unit"
    assert code =~ "elmc_tuple2" or code =~ "tuple2"
    refute code =~ "elmc_fn_Main_Bar"
  end
end
