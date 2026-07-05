defmodule Elmc.ConstructorTagCaseDeferredStringOutTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.ConstructorTagCase
  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  defp direction_branches do
    [
      %{pattern: %{kind: :constructor, name: "North", tag: 1}, expr: %{op: :string_literal, value: "N"}},
      %{pattern: %{kind: :constructor, name: "South", tag: 2}, expr: %{op: :string_literal, value: "S"}},
      %{pattern: %{kind: :constructor, name: "East", tag: 3}, expr: %{op: :string_literal, value: "E"}},
      %{pattern: %{kind: :constructor, name: "West", tag: 4}, expr: %{op: :string_literal, value: "W"}}
    ]
  end

  test "deferred string box allocates directly into function out" do
    env =
      %{"direction" => "direction"}
      |> Map.put(:__rc_catch__, true)
      |> RcRuntimeEmit.function_tail_env()

    {code, out, _counter} =
      ConstructorTagCase.compile_boxed_subject(
        %{op: :var, name: "direction"},
        direction_branches(),
        env,
        0
      )

    assert code =~ "*out = &native_str_immortal_"
    assert code =~ "&native_str_immortal_"
    refute code =~ "ELMC_FN_OUT"
    refute code =~ "elmc_new_string(out, case_str_"
    refute code =~ "ElmcValue *tmp_"
    refute String.match?(code, ~r/\*out = tmp_/)
  end
end
