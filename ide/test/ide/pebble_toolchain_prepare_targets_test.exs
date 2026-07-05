defmodule Ide.PebbleToolchain.PrepareTargetsTest do
  use ExUnit.Case, async: true

  alias Ide.PebbleToolchain.Prepare

  test "resolve_target_platforms keeps only requested emulator model when single_platform_only" do
    assert {:ok, ["emery"]} =
             Prepare.resolve_target_platforms("watchface",
               target_platforms: ["emery"],
               single_platform_only: true
             )
  end

  test "resolve_target_platforms normalizes watch model ids to lowercase" do
    assert {:ok, ["emery"]} =
             Prepare.resolve_target_platforms("watchface",
               target_platforms: ["Emery"],
               single_platform_only: true
             )
  end

  test "resolve_target_platforms rejects unknown models for emulator packaging" do
    assert {:error, {:invalid_emulator_target, "not-a-watch"}} =
             Prepare.resolve_target_platforms("watchface",
               target_platforms: ["not-a-watch"],
               single_platform_only: true
             )
  end

  test "resolve_target_platforms still defaults to all models for publish-style packaging" do
    assert {:ok, platforms} =
             Prepare.resolve_target_platforms("watchface", target_platforms: ["not-a-watch"])

    assert "emery" in platforms
    assert "basalt" in platforms
    assert length(platforms) > 2
  end
end
