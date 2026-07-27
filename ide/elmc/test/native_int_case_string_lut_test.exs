defmodule Elmc.NativeIntCaseStringLutTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Native.IntCase
  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  defp month_branches do
    months =
      ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov)
      |> Enum.with_index(1)
      |> Enum.map(fn {label, month} ->
        %{
          pattern: %{kind: :int, value: month},
          expr: %{op: :string_literal, value: label}
        }
      end)

    months ++ [%{pattern: %{kind: :wildcard}, expr: %{op: :string_literal, value: "Dec"}}]
  end

  test "int case with string literals compiles to immortal ElmcValue lut and one assign" do
    env =
      %{"month" => "month"}
      |> Map.put(:__native_rc_out__, true)
      |> RcRuntimeEmit.rc_catch_env()
      |> RcRuntimeEmit.function_tail_env()

    {code, _out, _counter} =
      IntCase.compile(%{op: :var, name: "month"}, month_branches(), env, 0)

    assert code =~ "static ElmcValue native_str_immortal_lut_"
    assert code =~ ~s("Jan")
    assert code =~ ~s("Nov")
    assert code =~ ~s("Dec")
    assert code =~ "*out = &native_str_immortal_lut_"
    refute code =~ "switch (month)"
    refute code =~ "elmc_new_string(out,"
    refute String.match?(code, ~r/elmc_new_string\(out, "Feb"\)/)
  end

  test "string lut pads index zero when keys start at one" do
    env =
      %{"month" => "month"}
      |> Map.put(:__native_rc_out__, true)
      |> RcRuntimeEmit.rc_catch_env()
      |> RcRuntimeEmit.function_tail_env()

    {code, _out, _counter} =
      IntCase.compile(%{op: :var, name: "month"}, month_branches(), env, 0)

    assert code =~ "static ElmcValue native_str_immortal_lut_1[13] = {"
    assert code =~ ~s/"Dec", 3 /
    assert code =~ ~s/"Jan", 3 /
  end
end
