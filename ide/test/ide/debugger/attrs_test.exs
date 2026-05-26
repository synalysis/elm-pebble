defmodule Ide.Debugger.AttrsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.Attrs

  test "parse_checkbox_bool accepts common truthy values" do
    assert Attrs.parse_checkbox_bool("on")
    refute Attrs.parse_checkbox_bool("off")
  end

  test "parse_tick_interval_ms clamps and defaults" do
    assert Attrs.parse_tick_interval_ms(50) == 1_000
    assert Attrs.parse_tick_interval_ms(500) == 500
  end

  test "parse_optional_cursor_seq" do
    assert Attrs.parse_optional_cursor_seq(3) == 3
    assert Attrs.parse_optional_cursor_seq("5") == 5
    assert Attrs.parse_optional_cursor_seq("bad") == nil
    assert Attrs.parse_optional_cursor_seq(-1) == nil
  end
end
