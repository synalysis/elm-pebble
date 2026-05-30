defmodule Ide.Resources.CtorNamingTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.CtorNaming

  test "normalize_base_name preserves PascalCase identifiers" do
    assert CtorNaming.normalize_base_name("PokeballOpen") == "PokeballOpen"
    assert CtorNaming.normalize_base_name("hour_hand") == "HourHand"
  end

  test "ctor combines fixed prefix and normalized base name" do
    assert CtorNaming.ctor(:bitmap_static, "hour_hand") == "BitmapStaticHourHand"
    assert CtorNaming.ctor(:bitmap_animated, "sparkle") == "BitmapAnimatedSparkle"
    assert CtorNaming.ctor(:vector_static, "bird") == "VectorStaticBird"
    assert CtorNaming.ctor(:vector_animated, "rain") == "VectorAnimatedRain"
  end

  test "legacy animation Anim prefix migrates to BitmapAnimated base" do
    assert CtorNaming.legacy_base_from_ctor("Anim100", :bitmap_animated) == "100"
    assert CtorNaming.ctor(:bitmap_animated, "100") == "BitmapAnimated100"
  end

  test "ensure_row upgrades legacy ctor names" do
    row = %{"ctor" => "Charmander", "filename" => "Charmander.png"}

    assert %{"ctor" => "BitmapStaticCharmander", "base_name" => "Charmander"} =
             CtorNaming.ensure_row!(row, :bitmap_static)
  end

  test "unique_ctor suffixes base on collision" do
    entries = [%{"ctor" => "BitmapStaticLogo"}]

    assert CtorNaming.unique_ctor(:bitmap_static, "Logo", entries) == "BitmapStaticLogo1"
  end
end
