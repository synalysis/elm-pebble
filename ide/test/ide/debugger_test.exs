defmodule Ide.DebuggerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  @tag :integration
  test "integration suite lives under test/ide/debugger/integration/" do
    integration_dir = Path.join([__DIR__, "debugger", "integration"])
    files = Path.wildcard(Path.join(integration_dir, "*_test.exs"))
    assert length(files) >= 4
  end
end
