defmodule IdeWeb.WorkspaceLive.ToolchainPresenterTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  test "render_capture_all_output handles embedded close result" do
    output =
      ToolchainPresenter.render_capture_all_output(%{
        captured: [],
        failed: [{"aplite", :emulator_not_ready}],
        results: [{"aplite", {:error, :emulator_not_ready}}],
        close_result: {:ok, :embedded}
      })

    assert output =~ "emulator_close: ok (embedded)"
    assert output =~ "[error] aplite"
  end

  test "render_capture_all_output handles external close result" do
    output =
      ToolchainPresenter.render_capture_all_output(%{
        captured: [],
        failed: [],
        results: [],
        close_result: {:ok, %{exit_code: 0}}
      })

    assert output =~ "emulator_close: ok (exit_code=0)"
  end
end
