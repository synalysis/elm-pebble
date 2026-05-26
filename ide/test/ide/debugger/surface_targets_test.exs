defmodule Ide.Debugger.SurfaceTargetsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SurfaceTargets

  test "normalize maps protocol and phone labels to companion" do
    assert SurfaceTargets.normalize("protocol") == :companion
    assert SurfaceTargets.normalize("phone") == :companion
    assert SurfaceTargets.normalize("watch") == :watch
    assert SurfaceTargets.normalize(nil) == :watch
  end

  test "normalize_optional returns nil for blank input" do
    assert SurfaceTargets.normalize_optional(nil) == nil
    assert SurfaceTargets.normalize_optional("") == nil
    assert SurfaceTargets.normalize_optional("watch") == :watch
  end

  test "source_root and replay_label" do
    assert SurfaceTargets.source_root(:companion) == "phone"
    assert SurfaceTargets.replay_label(nil) == "all"
    assert SurfaceTargets.replay_label(:watch) == "watch"
  end

  test "normalize_source_root" do
    assert SurfaceTargets.normalize_source_root(%{"source_root" => "protocol"}) == "protocol"
    assert SurfaceTargets.normalize_source_root(%{}) == "watch"
  end

  test "tick_targets" do
    assert SurfaceTargets.tick_targets(nil) == [:watch, :companion, :phone]
    assert SurfaceTargets.tick_targets(:watch) == [:watch]
  end
end

