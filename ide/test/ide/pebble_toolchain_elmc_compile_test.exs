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

  test "watch_compile_opts prunes dead generic view for aplite-only apps" do
    opts = Elmc.watch_compile_opts("/tmp/out", ["aplite"])

    refute opts[:direct_render_only]
    assert opts[:prune_direct_generic] == true
  end

  test "watch_compile_opts defaults to size codegen profile" do
    opts = Elmc.watch_compile_opts("/tmp/out", ["aplite", "basalt"])

    assert opts[:codegen_profile] == :size
  end

  test "watch_compile_opts uses balanced profile when optimize_for_size is false" do
    opts = Elmc.watch_compile_opts("/tmp/out", ["aplite"], %{optimize_for_size: false})

    assert opts[:codegen_profile] == :balanced
  end

  test "watch_compile_opts uses size profile when optimize_for_size is set" do
    opts = Elmc.watch_compile_opts("/tmp/out", ["aplite"], %{optimize_for_size: true})

    assert opts[:codegen_profile] == :size
  end

  test "codegen_profile_for_project_dir defaults to size without release_defaults" do
    tmp = Path.join(System.tmp_dir!(), "pebble-elmc-profile-default-#{System.unique_integer([:positive])}")
    watch = Path.join(tmp, "watch")
    File.mkdir_p!(watch)

    File.write!(
      Path.join(tmp, "elm-pebble.project.json"),
      Jason.encode!(%{
        "release_defaults" => %{
          "target_platforms" => ["flint"]
        }
      })
    )

    on_exit(fn -> File.rm_rf(tmp) end)

    assert Elmc.optimize_for_size?(watch)
    assert Elmc.codegen_profile_for_project_dir(watch) == :size
  end

  test "codegen_profile_for_project_dir reads optimize_for_size from elm-pebble.project.json" do
    tmp = Path.join(System.tmp_dir!(), "pebble-elmc-profile-#{System.unique_integer([:positive])}")
    watch = Path.join(tmp, "watch")
    File.mkdir_p!(watch)

    File.write!(
      Path.join(tmp, "elm-pebble.project.json"),
      Jason.encode!(%{
        "release_defaults" => %{
          "optimize_for_size" => true,
          "target_platforms" => ["flint"]
        }
      })
    )

    on_exit(fn -> File.rm_rf(tmp) end)

    assert Elmc.optimize_for_size?(watch)
    assert Elmc.codegen_profile_for_project_dir(watch) == :size

    compile_opts =
      %{}
      |> Map.put_new(:codegen_profile, Elmc.codegen_profile_for_project_dir(watch, %{}))
      |> then(&Elmc.watch_compile_opts("/tmp/out", ["flint"], &1))

    assert compile_opts[:codegen_profile] == :size
  end

  test "codegen_profile_for_project_dir uses balanced when optimize_for_size is false" do
    tmp = Path.join(System.tmp_dir!(), "pebble-elmc-profile-balanced-#{System.unique_integer([:positive])}")
    watch = Path.join(tmp, "watch")
    File.mkdir_p!(watch)

    File.write!(
      Path.join(tmp, "elm-pebble.project.json"),
      Jason.encode!(%{
        "release_defaults" => %{
          "optimize_for_size" => false,
          "target_platforms" => ["flint"]
        }
      })
    )

    on_exit(fn -> File.rm_rf(tmp) end)

    refute Elmc.optimize_for_size?(watch)
    assert Elmc.codegen_profile_for_project_dir(watch) == :balanced
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

  test "watch_target_platforms normalizes project json platform order" do
    tmp = Path.join(System.tmp_dir!(), "pebble-elmc-platforms-#{System.unique_integer([:positive])}")
    watch = Path.join(tmp, "watch")
    File.mkdir_p!(watch)

    File.write!(
      Path.join(tmp, "elm-pebble.project.json"),
      Jason.encode!(%{
        "release_defaults" => %{
          "target_platforms" => ["Chalk", "basalt", "aplite"]
        }
      })
    )

    on_exit(fn -> File.rm_rf(tmp) end)

    assert Elmc.watch_target_platforms(watch, ["gabbro"]) == ["aplite", "basalt", "chalk"]
  end

  test "normalize_stamp_platforms sorts and downcases" do
    assert Elmc.normalize_stamp_platforms(["Chalk", " basalt ", "aplite", "chalk"]) ==
             ["aplite", "basalt", "chalk"]
  end

  test "compile_project_succeeded? accepts CLI project_run maps" do
    assert Elmc.compile_project_succeeded?(%{status: :ok, output: "ok"})
    assert Elmc.compile_project_succeeded?({:ok, %{}})
    refute Elmc.compile_project_succeeded?(%{status: :error})
    refute Elmc.compile_project_succeeded?({:error, :boom})
  end

  test "generate_sources reuses stamped .elmc-build without recompiling" do
    tmp = Path.join(System.tmp_dir!(), "pebble-elmc-reuse-#{System.unique_integer([:positive])}")
    watch = Path.join(tmp, "watch")
    out = Path.join(watch, ".elmc-build")
    c_dir = Path.join(out, "c")
    File.mkdir_p!(c_dir)

    File.write!(
      Path.join(tmp, "elm-pebble.project.json"),
      Jason.encode!(%{
        "release_defaults" => %{"target_platforms" => ["basalt"]}
      })
    )

    File.write!(Path.join(watch, "elm.json"), "{}")
    File.write!(Path.join(c_dir, "elmc_generated.c"), "/* stamped reuse fixture */\n")

    platforms = ["basalt"]

    compile_opts =
      Elmc.watch_compile_opts(out, platforms, %{
        prod: true,
        debug_usage_policy: :error,
        plan_ir_mode: :primary,
        plan_ir_strict: true,
        codegen_profile: :size
      })

    :ok = Elmc.write_compile_stamp(watch, out, compile_opts, platforms)
    mtime_before = File.stat!(Path.join(c_dir, "elmc_generated.c")).mtime

    app = Path.join(tmp, "app")
    File.mkdir_p!(app)

    assert :ok =
             Elmc.generate_sources(watch, app, tmp,
               target_platforms: platforms,
               prod: true,
               debug_usage_policy: :error,
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               reuse_elmc_build: true
             )

    assert File.stat!(Path.join(c_dir, "elmc_generated.c")).mtime == mtime_before

    staged = Path.join(app, "src/c/elmc/c/elmc_generated.c")
    assert File.read!(staged) == "/* stamped reuse fixture */\n"

    on_exit(fn -> File.rm_rf(tmp) end)
  end
end
