defmodule Ide.Handheld.MeowLinkTest do
  use ExUnit.Case, async: true

  alias Ide.Handheld.MeowLink

  test "frames the manifest and the image with their sizes" do
    frame = MeowLink.request("display", "{\"id\":\"display\"}", "MEOW")

    assert frame ==
             "MEOW install display 16 4\n" <> "{\"id\":\"display\"}" <> "MEOW"
  end

  test "accepts the device reply" do
    assert MeowLink.accept("MEOW ok\n") == :ok
    assert MeowLink.accept("MEOW err sd\n") == {:error, "sd"}
  end
end
