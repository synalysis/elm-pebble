defmodule Ide.Debugger.BootstrapInitTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.BootstrapInit

  test "companion bootstrap flags defer surface effects only" do
    state = BootstrapInit.with_companion_bootstrap_flags(%{})

    refute BootstrapInit.parser_only?(state)
    assert BootstrapInit.defer_surface_effects?(state)
    assert Map.get(state, :debugger_skip_blocking_compile) == true

    cleared = BootstrapInit.clear_companion_bootstrap_flags(state)
    refute BootstrapInit.defer_surface_effects?(cleared)
  end
end
