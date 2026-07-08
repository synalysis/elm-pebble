defmodule Ide.PebbleToolchainElmcCompileTest do
  use ExUnit.Case, async: true

  alias Ide.PebbleToolchain.Elmc

  test "watch_compile_opts enables pebble production flags for multi-platform apps" do
    opts = Elmc.watch_compile_opts("/tmp/out", ["aplite", "basalt"])

    assert opts[:pebble_int32] == true
    assert opts[:prune_runtime] == true
    assert opts[:prune_native_wrappers] == true
    assert opts[:prune_direct_generic] == true
    assert opts[:direct_render_only] == false
    assert opts[:plan_ir_mode] == :primary
    assert opts[:plan_ir_strict] == true
    assert opts[:prod] == true
  end

  test "watch_compile_opts enables direct render for color-only multi-platform apps" do
    opts = Elmc.watch_compile_opts("/tmp/out", ["basalt", "chalk", "gabbro"])

    assert opts[:direct_render_only] == true
    refute opts[:prune_direct_generic]
  end

  test "target_platforms_for_project_dir reads release_defaults from workspace config" do
    tmp = Path.join(System.tmp_dir!(), "pebble-elmc-opts-#{System.unique_integer([:positive])}")
    watch = Path.join(tmp, "watch")
    File.mkdir_p!(watch)

    File.write!(
      Path.join(tmp, "elm-pebble.project.json"),
      Jason.encode!(%{
        "release_defaults" => %{
          "target_platforms" => ["aplite", "basalt", "chalk"]
        }
      })
    )

    on_exit(fn -> File.rm_rf(tmp) end)

    assert Elmc.target_platforms_for_project_dir(watch) == ["aplite", "basalt", "chalk"]
    refute Elmc.target_platforms_for_project_dir("/tmp/no-elm-pebble-project-dir")
  end
end
