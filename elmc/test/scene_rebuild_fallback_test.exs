defmodule Elmc.SceneRebuildFallbackTest do
  @moduledoc """
  Failed scene rebuilds must restore the last good encoded frame.

  Without pool double-buffering, `abort_build` detached the only scene buffer and
  the app template filled white → lasting gray face under heap pressure.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.BufferFree
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.PrepareRebuild
  alias Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.AppStruct
  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.EnsureFinish
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.SceneFields

  test "app struct carries rebuild fallback counts under scene cache" do
    body = AppStruct.body()
    assert body =~ "scene_rebuild_fallback_slot"
    assert body =~ "scene_rebuild_fallback_byte_count"
    assert body =~ "scene_rebuild_fallback_command_count"
  end

  test "init clears rebuild fallback fields" do
    body = SceneFields.body()
    assert body =~ "scene_rebuild_fallback_byte_count = 0"
    assert body =~ "scene_rebuild_fallback_command_count = 0"
  end

  test "prepare_scene_rebuild flips pool slot and records fallback when pool>=2" do
    body = PrepareRebuild.body()
    assert body =~ "ELMC_PEBBLE_SCENE_POOL_SLOTS >= 2"
    assert body =~ "scene_rebuild_fallback_byte_count = app->scene.byte_count"
    assert body =~ "app->scene.pool_slot = app->scene.pool_slot == 0 ? 1 : 0"
  end

  test "abort_build restores fallback frame instead of blanking" do
    body = BufferFree.body()
    assert body =~ "scene_rebuild_fallback_byte_count > 0"
    assert body =~ "app->scene.byte_count = app->scene_rebuild_fallback_byte_count"
    assert body =~ "app->scene.command_count = app->scene_rebuild_fallback_command_count"
    # Dirty-region path also restores prev_scene.
    assert body =~ "app->prev_scene.bytes && app->prev_scene.byte_count > 0"
  end

  test "successful ensure clears fallback counts" do
    body = EnsureFinish.body()
    assert body =~ "scene_rebuild_fallback_byte_count = 0"
    assert body =~ "scene_rebuild_fallback_command_count = 0"
  end

  test "app template skips white fill when scene bytes are empty" do
    template =
      Path.expand("../../ide/priv/pebble_app_template/src/c/pebble_app_template.c", __DIR__)
      |> File.read!()

    assert template =~ "keep the previous framebuffer until a good scene is available again"
    assert template =~ "if (s_elm_app.scene.byte_count <= 0)"
  end
end
