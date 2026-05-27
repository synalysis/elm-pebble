defmodule Ide.Emulator.ScreenshotTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Screenshot

  test "capture_timeout_ms delegates to firmware sizing" do
    assert Screenshot.capture_timeout_ms("chalk") >= 20_000
    assert Screenshot.capture_timeout_ms("unknown-platform") >= 20_000
  end

end
