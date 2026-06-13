defmodule Ide.Debugger.EmulatorRcFailApplyTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.EmulatorRcFailApply

  setup do
    slug = "emulator-rc-fail-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)
    on_exit(fn -> Debugger.forget_project(slug) end)
    %{slug: slug}
  end

  test "patches watch model with elmc_last_fail fields", %{slug: slug} do
    assert {:ok, state} = EmulatorRcFailApply.apply(slug, %{code: 1, line: 42})

    model = get_in(state, [:watch, :model])
    assert model["elmc_last_fail_code"] == 1
    assert model["elmc_last_fail_line"] == 42
  end

  test "ignores zero code", %{slug: slug} do
    assert {:ok, state} = EmulatorRcFailApply.apply(slug, %{code: 0, line: 10})
    refute Map.has_key?(get_in(state, [:watch, :model]) || %{}, "elmc_last_fail_code")
  end
end
