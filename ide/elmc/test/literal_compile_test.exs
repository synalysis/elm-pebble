defmodule Elmc.LiteralCompileTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.LiteralCompile
  alias Elmc.Backend.CCodegen.ValueSlots

  setup do
    ValueSlots.reset()
    :ok
  end

  test "RC literals allocate into owned slots for failure cleanup" do
    env = %{__rc_required__: true, __rc_catch__: true}

    {code, var, _counter} =
      LiteralCompile.compile(
        %{op: :c_int_expr, value: "ELMC_RENDER_OP_FILL_CIRCLE"},
        env,
        0
      )

    assert var == "owned[0]"
    assert code =~ "Rc = elmc_new_int(&owned[0], ELMC_RENDER_OP_FILL_CIRCLE)"
    refute code =~ "tmp_"
  end

  test "non-RC literals keep standalone tmp vars" do
    env = %{}

    {_code, var, _counter} =
      LiteralCompile.compile(%{op: :int_literal, value: 4}, env, 0)

    assert var == "tmp_1"
  end
end
