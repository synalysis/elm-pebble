defmodule Elmc.ObjectTextEstimateTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.ObjectTextEstimate

  @fixture_root Path.expand("fixtures/pebble_surface_project/.elmc-build", __DIR__)

  test "estimate reports generated and app object text for staged elmc sources" do
    estimate = ObjectTextEstimate.estimate(@fixture_root)

    case estimate do
      %{"available" => true} ->
        assert is_integer(estimate["generated_text"])
        assert estimate["generated_text"] > 0
        assert is_integer(estimate["elmc_app_text"])
        assert estimate["elmc_app_text"] >= estimate["generated_text"]

      %{"available" => false, "reason" => reason} ->
        # elmc CI runners do not install the Pebble ARM toolchain; local dev with
        # ~/.pebble-sdk still exercises the full object-text gate.
        assert reason =~ "arm-none-eabi-gcc" or reason =~ "no C sources"
    end
  end
end
