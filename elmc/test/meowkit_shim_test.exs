defmodule Elmc.MeowkitShimTest do
  use ExUnit.Case, async: true

  test "copies the shared handheld shim for meowkit and flipper" do
    dest =
      Path.join(System.tmp_dir!(), "elmc-handheld-#{System.unique_integer([:positive])}")

    assert :ok = Elmc.Backend.Meowkit.Shim.write(dest, ["meowkit", "flipper"])
    assert File.exists?(Path.join(dest, "handheld/elmc_handheld_shim.c"))
    assert File.exists?(Path.join(dest, "handheld/handheld_host.h"))
    assert File.exists?(Path.join(dest, "handheld/application.fam"))
    assert Elmc.Backend.Meowkit.Shim.targets(%{target: "c,meowkit"}) == ["meowkit"]
    assert Elmc.Backend.Meowkit.Shim.targets(%{target: :flipper}) == ["flipper"]
  end
end
