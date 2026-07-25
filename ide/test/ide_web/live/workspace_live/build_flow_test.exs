defmodule IdeWeb.WorkspaceLive.BuildFlowTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.BuildFlow

  test "run_build_pipeline_for_root skips elmc compile for protocol after elm check" do
    workspace = tmp_protocol_workspace!()

    assert {:ok, result} =
             BuildFlow.run_build_pipeline_for_root(
               "yes",
               "protocol",
               Path.join(workspace, "protocol"),
               false
             )

    assert result.status == :ok
    assert result.check.status == :ok
    assert result.compile.status == :ok
    assert result.compile.output =~ "elm make"
    assert result.manifest.status == :ok
  end

  test "run_build_pipeline_for_root skips elmc compile for phone after elm check" do
    workspace = tmp_phone_workspace!()

    assert {:ok, result} =
             BuildFlow.run_build_pipeline_for_root(
               "yes",
               "phone",
               Path.join(workspace, "phone"),
               false
             )

    assert result.status == :ok
    assert result.check.status == :ok
    assert result.compile.status == :ok
    assert result.compile.output =~ "elm make"
    assert result.compile.output =~ "watch only"
    assert result.manifest.status == :ok
    refute result.compile.output =~ "[elmc]"
  end

  test "package failure explains Aplite memory overflow" do
    reason =
      {:pebble_build_failed,
       %{
         cwd: "/tmp/app",
         command: "pebble build",
         exit_code: 1,
         output: "region `APP' overflowed by 1234 bytes"
       }}

    output = BuildFlow.render_package_failure(reason, ["aplite", "basalt"])

    assert output =~ "PBW packaging failed"
    assert output =~ "memory-region overflow"
    assert output =~ "Aplite is enabled"
    assert output =~ "region `APP' overflowed"
  end

  test "package output issues promote linker overflow details" do
    output = """
    [135/136] Linking aplite | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/aplite/pebble-app.elf
    ld: build/aplite/pebble-app.elf section `.text' will not fit in region `APP'
    ld: region `APP' overflowed by 12076 bytes
    collect2: error: ld returned 1 exit status
    """

    assert [
             %{
               title: "PBW too large for Aplite",
               message: message,
               detail: "target=aplite overflow=12076 bytes"
             }
           ] = BuildFlow.package_output_issues(output)

    assert message =~ "Aplite is enabled"
  end

  test "package output issues use overflowing target, not earlier link target" do
    output = """
    [133/136] Linking gabbro | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/gabbro/pebble-app.elf
    [135/136] Linking aplite | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/aplite/pebble-app.elf
    ld: build/aplite/pebble-app.elf section `.text' will not fit in region `APP'
    ld: region `APP' overflowed by 12076 bytes
    collect2: error: ld returned 1 exit status
    """

    assert [
             %{
               title: "PBW too large for Aplite",
               detail: "target=aplite overflow=12076 bytes"
             }
           ] = BuildFlow.package_output_issues(output)
  end

  test "package failure explains bitmap resource packaging failures" do
    reason =
      {:pebble_build_failed,
       %{
         cwd: "/tmp/app",
         command: "pebble build",
         exit_code: 1,
         output: """
         [ 9/29] Compiling basalt | reso: resources/bitmaps/BadLogo.png -> build/basalt/resources/bitmaps/BadLogo.png.BITMAP_BADLOGO.reso
         File ".../png2pblpng.py", line 158, in get_palette_for_png
           input_png.preamble()
         Build failed
         """
       }}

    output = BuildFlow.render_package_failure(reason, ["basalt"])

    assert output =~ "PBW packaging failed"
    assert output =~ "BadLogo.png"
    assert output =~ "could not read bitmap"
  end

  test "package output issues explain bitmap resource packaging failures" do
    output = """
    [ 9/29] Compiling basalt | reso: resources/bitmaps/BadLogo.png -> build/basalt/resources/bitmaps/BadLogo.png.BITMAP_BADLOGO.reso
    File ".../png2pblpng.py", line 158, in get_palette_for_png
      input_png.preamble()
    Build failed
    """

    assert [
             %{
               title: "Bitmap resource packaging failed",
               message: message,
               detail: "resource=BadLogo.png"
             }
           ] = BuildFlow.package_output_issues(output)

    assert message =~ "BadLogo.png"
  end

  defp tmp_protocol_workspace! do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "build_flow_protocol_#{System.unique_integer([:positive])}"
      )

    protocol_root = Path.join(workspace, "protocol")
    File.mkdir_p!(Path.join(protocol_root, "src/Companion"))

    File.write!(
      Path.join(protocol_root, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(protocol_root, "src/Companion/Types.elm"),
      """
      module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

      type WatchToPhone
          = Ping

      type PhoneToWatch
          = Pong
      """
    )

    File.write!(
      Path.join(protocol_root, "src/Companion/Watch.elm"),
      """
      module Companion.Watch exposing (onPhoneToWatch, sendWatchToPhone)

      import Companion.Types exposing (PhoneToWatch, WatchToPhone)
      import Pebble.Internal.Companion as Companion

      onPhoneToWatch _ =
          Sub.none

      sendWatchToPhone _ =
          Cmd.none
      """
    )

    on_exit(fn -> File.rm_rf(workspace) end)
    workspace
  end

  defp tmp_phone_workspace! do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "build_flow_phone_#{System.unique_integer([:positive])}"
      )

    phone_root = Path.join(workspace, "phone")
    File.mkdir_p!(Path.join(phone_root, "src"))

    File.write!(
      Path.join(phone_root, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/browser" => "1.0.2", "elm/html" => "1.0.0"},
          "indirect" => %{
            "elm/json" => "1.1.3",
            "elm/time" => "1.0.0",
            "elm/url" => "1.0.0",
            "elm/virtual-dom" => "1.0.3"
          }
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(phone_root, "src/CompanionApp.elm"),
      """
      module CompanionApp exposing (main)

      import Browser
      import Html exposing (text)

      main =
          Browser.sandbox
              { init = ()
              , update = \\_ model -> model
              , view = \\_ -> text "ok"
              }
      """
    )

    on_exit(fn -> File.rm_rf(workspace) end)
    workspace
  end
end
