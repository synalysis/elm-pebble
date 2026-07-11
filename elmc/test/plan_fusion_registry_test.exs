defmodule Elmc.PlanFusionRegistryTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Fusion.{CEmit, Registry}

  test "CEmit registers every fusion provider" do
    assert CEmit.providers() == Registry.providers()
  end
end
