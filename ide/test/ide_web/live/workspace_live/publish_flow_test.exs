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

  test "store_release_notes returns trimmed changelog for App Store submit" do
    summary = %{"changelog" => "  Fixed layout on chalk.\n"}

    assert PublishFlow.store_release_notes(summary) == "Fixed layout on chalk."
    assert PublishFlow.store_release_notes(%{}) == ""
  end

  test "publish summary stays idle before validation checks run" do
    readiness = [%{target: "basalt", count: 1, status: :ok}]

    assert %{status: :idle, blockers: 0, passed: 0} =
             PublishFlow.publish_summary([], [], readiness)
  end

  test "publish readiness follows configured target platforms" do
    project = %{release_defaults: %{"target_platforms" => ["basalt", "chalk"]}}
    shots = [%{emulator_target: "basalt"}]

    assert [
             %{target: "basalt", count: 1, status: :ok},
             %{target: "chalk", count: 0, status: :missing}
           ] = PublishFlow.publish_readiness(project, shots)

    refute Enum.any?(PublishFlow.publish_readiness(project, shots), &(&1.target == "aplite"))
  end

  test "stage_publish_screenshots copies screenshots with platform-prefixed filenames" do
    root =
      Path.join(System.tmp_dir!(), "ide_publish_flow_test_#{System.unique_integer([:positive])}")

    app_root = Path.join(root, "app")
    source_dir = Path.join(root, "source")
    File.mkdir_p!(app_root)
    File.mkdir_p!(source_dir)
    on_exit(fn -> File.rm_rf(root) end)

    emery = Path.join(source_dir, "shot-a.png")
    chalk = Path.join(source_dir, "chalk_shot_20260519.png")
    File.write!(emery, png_header(200, 228))
    File.write!(chalk, png_header(180, 180))

    assert {:ok, [staged_emery, staged_chalk]} =
             PublishFlow.stage_publish_screenshots(app_root, [
               {"emery", [%{absolute_path: emery}]},
               {"chalk", [%{absolute_path: chalk}]}
             ])

    assert Path.basename(staged_emery) == "emery_1_shot-a.png"
    assert Path.basename(staged_chalk) == "chalk_shot_20260519.png"
    assert File.regular?(staged_emery)
    assert File.regular?(staged_chalk)
  end

  test "stage_publish_screenshots skips screenshots with wrong dimensions" do
    root =
      Path.join(System.tmp_dir!(), "ide_publish_flow_test_#{System.unique_integer([:positive])}")

    app_root = Path.join(root, "app")
    source_dir = Path.join(root, "source")
    File.mkdir_p!(app_root)
    File.mkdir_p!(source_dir)
    on_exit(fn -> File.rm_rf(root) end)

    valid = Path.join(source_dir, "valid.png")
    invalid = Path.join(source_dir, "invalid.png")
    File.write!(valid, png_header(144, 168))
    File.write!(invalid, png_header(148, 172))

    assert {:ok, [staged]} =
             PublishFlow.stage_publish_screenshots(app_root, [
               {"basalt", [%{absolute_path: invalid}, %{absolute_path: valid}]}
             ])

    assert Path.basename(staged) == "basalt_1_valid.png"
  end

  defp png_header(width, height) do
    <<0x89, "PNG\r\n", 0x1A, "\n", 0::32, "IHDR", width::32, height::32, 0::32>>
  end
end
