defmodule Elmc.SpecialValuesCmdAliasTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.SpecialValues.Core
  alias Elmc.Backend.CCodegen.SpecialValues.Dispatcher

  test "package-qualified Random.generate resolves to pebble cmd special value" do
    assert Core.normalize_special_target("Pkg.app.Random.generate") == "Random.generate"

    assert %{
             op: :pebble_cmd,
             kind: %{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_RANDOM_GENERATE"},
             params: [_tag]
           } =
             Dispatcher.special_value_from_target("Pkg.app.Random.generate", [
               %{op: :var, name: "RandomGenerated"},
               %{op: :call, name: "ignore", args: []}
             ])
  end
end
