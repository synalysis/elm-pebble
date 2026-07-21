defmodule Elmc.FixtureCodegenDualBackendTest do
  use ExUnit.Case

  alias Elmc.Test.FixtureCodegen

  @moduletag timeout: 600_000

  @elmc_bulk_fixture_prefix "wasm_"
  @elmc_bulk_fixture_excluded ~w(rc_track_2048_pebble_project)

  @tag :fixture_codegen
  test "all elmc fixture projects compile end-to-end" do
    failures =
      FixtureCodegen.fixture_dirs()
      |> Enum.reject(&String.starts_with?(&1, @elmc_bulk_fixture_prefix))
      |> Enum.reject(&(&1 in @elmc_bulk_fixture_excluded))
      |> Enum.flat_map(fn fixture ->
        try do
          FixtureCodegen.compile_elmc!(fixture)
          []
        rescue
          exception -> [{fixture, Exception.message(exception)}]
        end
      end)

    assert failures == [],
           "elmc fixture compile failures: #{inspect(failures, limit: 10)}"
  end

  @tag :fixture_codegen
  test "portable fixture projects compile on elmx" do
    failures =
      Enum.flat_map(FixtureCodegen.elmx_compile_fixture_dirs(), fn fixture ->
        try do
          FixtureCodegen.compile_elmx!(fixture)
          []
        rescue
          exception -> [{fixture, Exception.message(exception)}]
        end
      end)

    assert failures == [],
           "elmx fixture compile failures: #{inspect(failures, limit: 10)}"
  end
end
