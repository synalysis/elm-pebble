defmodule Elmc.PebbleFixtureCodegenGateTest do
  use ExUnit.Case

  alias Elmc.Test.FixtureCodegen

  @tag :fixture_codegen
  @tag :pebble_fixture
  test "pebble smoke fixtures compile on elmc" do
    for fixture <- FixtureCodegen.pebble_smoke_fixtures() do
      assert :ok = FixtureCodegen.compile_elmc!(fixture)
    end
  end

  @tag :fixture_codegen
  @tag :pebble_fixture
  test "simple_project compiles on elmx for pebble/core parity" do
    assert FixtureCodegen.compile_elmx!("simple_project")
  end
end
