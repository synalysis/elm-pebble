defmodule Ide.Emulator.Session.StartupTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Session.Startup

  test "app_uuid/2 returns nil without artifact path" do
    assert Startup.app_uuid(nil, "chalk") == nil
  end
end
