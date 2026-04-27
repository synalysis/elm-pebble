defmodule IdeWeb.WorkspaceLive.PublishFlowTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.PublishFlow

  test "default_release_summary reads version and tags from project defaults" do
    project = %{release_defaults: %{"version_label" => "1.2.3", "tags" => "utility"}}

    assert %{"version_label" => "1.2.3", "tags" => "utility"} =
             PublishFlow.default_release_summary(project)
  end

  test "bump_release_summary increments semver patch" do
    summary = %{"version_label" => "2.4.9", "tags" => "watchface"}

    assert %{"version_label" => "2.4.10", "tags" => "watchface"} =
             PublishFlow.bump_release_summary(summary)
  end

  test "bump_release_summary leaves non-semver unchanged" do
    summary = %{"version_label" => "beta", "tags" => "watchface"}

    assert ^summary = PublishFlow.bump_release_summary(summary)
  end
end
