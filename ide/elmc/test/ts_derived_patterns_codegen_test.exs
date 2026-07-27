defmodule Elmc.TsDerivedPatternsCodegenTest do
  use ExUnit.Case

  alias Elmc.Test.FixtureCodegen

  @fixture FixtureCodegen.ts_derived_fixture()

  @expected_main """
  { composeWithLambda = 3, constructorRefJust = Just 3, nestedCaseCtor = 9, nestedFieldCall = 3, qualifiedRefIdentity = 7, unicodeLen = 1 }
  """

  @tag :fixture_codegen
  @tag :ts_derived
  test "tree-sitter-derived fixture compiles on both backends" do
    assert :ok = FixtureCodegen.compile_elmc!(@fixture)
    assert FixtureCodegen.compile_elmx!(@fixture)
  end

  @tag :fixture_codegen
  @tag :ts_derived
  test "tree-sitter-derived patterns produce expected runtime values on elmx" do
    output = FixtureCodegen.run_elmx_main!(@fixture, revision: "ts-derived-test")

    assert String.trim(output) == String.trim(@expected_main)
  end

  @tag :fixture_codegen
  @tag :ts_derived
  test "tree-sitter-derived helper functions match expected semantics on elmx" do
    mod = FixtureCodegen.compile_elmx!(@fixture, revision: "ts-derived-probe")

    api = %{"child" => &apply(mod, :elmx_fn_TsDerivedPatterns_childHandler, [&1])}
    child = %{"getName" => fn s -> String.length(s) end}

    assert apply(mod, :elmx_fn_TsDerivedPatterns_nestedFieldCall, [api, child, "abc"]) == 3
    assert apply(mod, :elmx_fn_TsDerivedPatterns_composeWithLambda, [120]) == 3
    assert apply(mod, :elmx_fn_TsDerivedPatterns_qualifiedRefIdentity, [7]) == 7
    assert apply(mod, :elmx_fn_TsDerivedPatterns_constructorRefJust, [3]) == {:Just, 3}
    assert apply(mod, :elmx_fn_TsDerivedPatterns_nestedCaseCtor, [{:Just, {:Custom, 9}}]) == 9
    assert String.length(apply(mod, :elmx_fn_TsDerivedPatterns_unicodeMathAlpha, [])) == 1
  end
end
