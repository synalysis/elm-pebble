defmodule Ide.Debugger.StepMessageValueTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.StepMessageValue

  test "normalize returns nil for nil message value" do
    assert StepMessageValue.normalize(%{}, :watch, nil, %{}, fn -> %{} end) == nil
  end

  test "normalize passes through non-map values" do
    assert StepMessageValue.normalize(%{}, :watch, "Tick", %{}, fn -> %{} end) == "Tick"
  end
end
