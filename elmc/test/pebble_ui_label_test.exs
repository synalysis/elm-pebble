defmodule Elmc.Backend.Pebble.UiLabelTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Pebble.UiLabel

  test "maps only Pebble.Ui.Label constructors" do
    assert UiLabel.display_text("Pebble.Ui.WaitingForCompanion") ==
             "Waiting for companion app"

    assert UiLabel.display_text("WaitingForCompanion") == "Waiting for companion app"
    assert UiLabel.display_text(:WaitingForCompanion) == "Waiting for companion app"
  end

  test "does not invent text for other constructors or empty tags" do
    assert UiLabel.display_text("Main.WaitingForCompanion") == nil
    assert UiLabel.display_text("GotQuote") == nil
    assert UiLabel.display_text("") == nil
    assert UiLabel.display_text(0) == nil
  end
end
