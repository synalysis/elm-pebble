defmodule IdeWeb.ThemeContrastTest do
  use ExUnit.Case, async: true

  @app_css Path.expand("../../assets/css/app.css", __DIR__)

  test "dark and system themes remap emulator setup surfaces for contrast" do
    css = File.read!(@app_css)

    for theme <- [~s(body[data-ide-theme="dark"]), ~s(body[data-ide-theme="system"])] do
      assert css =~ "#{theme} .bg-amber-50"
      assert css =~ "#{theme} .bg-white\\/70"
      assert css =~ "#{theme} :is(.text-amber-900, .text-amber-800, .text-amber-700)"
      assert css =~ "#{theme} :is(.text-emerald-900, .text-emerald-800, .text-emerald-700)"
    end

    assert css =~ "background-color: #451a03"
    assert css =~ "color: #fde68a"
  end
end
