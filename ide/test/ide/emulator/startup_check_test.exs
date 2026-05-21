defmodule Ide.Emulator.StartupCheckTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ide.Emulator.StartupCheck

  test "logs embedded emulator startup status without crashing" do
    previous_level = Logger.level()
    Logger.configure(level: :info)

    log =
      capture_log(fn ->
        assert :ok = StartupCheck.log()
      end)

    Logger.configure(level: previous_level)

    assert log =~ "[embedded-emulator] startup check for"
    assert log =~ "[embedded-emulator]   Embedded emulator:"
  end
end
