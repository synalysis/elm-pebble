defmodule Elmc.DrawFieldCmdEncodingTest do
  use ExUnit.Case

  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.Pebble.Kinds

  test "fillCircle with point center encodes render op kind not runtime command id" do
    center = %{op: :var, name: "center"}
    radius = %{op: :int_literal, value: 3}
    color = %{op: :int_literal, value: 1}

    expr =
      SpecialValues.special_value_from_target("Pebble.Ui.fillCircle", [center, radius, color])

  assert %{op: :tuple2, left: %{op: :c_int_expr, value: "ELMC_RENDER_OP_FILL_CIRCLE"}} = expr
  refute inspect(expr) =~ "GET_CLOCK_STYLE"
  end

  test "generated render-op defines cover every draw kind id" do
    defines = Emit.generated_magic_number_defines()

    for {kind, id} <- Kinds.draw_kinds() do
      macro = kind |> Atom.to_string() |> String.upcase()
      assert defines =~ "#define ELMC_RENDER_OP_#{macro} #{id}"
    end
  end
end
