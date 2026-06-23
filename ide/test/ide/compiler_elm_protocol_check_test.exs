defmodule Ide.CompilerElmProtocolCheckTest do
  use ExUnit.Case, async: true

  alias Ide.Compiler

  test "check_source_root on protocol reports elm naming errors on save" do
    workspace = tmp_workspace!()

    assert {:ok, %{status: :error, diagnostics: diagnostics}} =
             Compiler.check_source_root("protocol-editor-#{System.unique_integer([:positive])}",
               workspace_root: workspace,
               source_root: "protocol"
             )

    assert Enum.any?(diagnostics, fn diag ->
             String.contains?(Map.get(diag, :message, ""), "NAMING ERROR") and
               Map.get(diag, :file) == "src/Companion/Types.elm"
           end)
  end

  test "check_source_root on protocol regenerates Internal.elm from Types.elm" do
    workspace = tmp_workspace_with_composite_watch_to_phone!()

    assert {:ok, %{status: :ok}} =
             Compiler.check_source_root(
               "protocol-composite-w2p-#{System.unique_integer([:positive])}",
               workspace_root: workspace,
               source_root: "protocol"
             )

    internal = File.read!(Path.join(workspace, "protocol/src/Companion/Internal.elm"))

    assert internal =~ "Decode.decodeValue (decodePoint \"send_point_field1\") value"
    refute internal =~ "Decode.field \"send_point_field1\" decodePoint"
  end

  test "check_source_root on protocol ignores watch-only Companion.Watch glue" do
    workspace = tmp_workspace_with_watch_glue!()

    assert {:ok, %{status: :ok, diagnostics: diagnostics}} =
             Compiler.check_source_root("protocol-watch-glue-#{System.unique_integer([:positive])}",
               workspace_root: workspace,
               source_root: "protocol"
             )

    refute Enum.any?(diagnostics, fn diag ->
             file = Map.get(diag, :file) || ""
             String.contains?(file, "Companion/Watch.elm")
           end)
  end

  defp tmp_workspace_with_composite_watch_to_phone! do
    workspace = tmp_workspace!()

    File.write!(
      Path.join(workspace, "protocol/src/Companion/Types.elm"),
      """
      module Companion.Types exposing (PhoneToWatch(..), Point, WatchToPhone(..))

      type alias Point =
          { x : Int, y : Int }

      type WatchToPhone
          = SendPoint Point

      type PhoneToWatch
          = Pong
      """
    )

    File.write!(
      Path.join(workspace, "protocol/src/Companion/Internal.elm"),
      """
      module Companion.Internal exposing (decodeWatchToPhonePayload)

      import Companion.Types exposing (..)
      import Json.Decode as Decode

      decodeWatchToPhonePayload _ _ =
          Decode.fail "stale"
      """
    )

    workspace
  end

  defp tmp_workspace_with_watch_glue! do
    workspace = tmp_workspace!()

    File.write!(
      Path.join(workspace, "protocol/src/Companion/Types.elm"),
      """
      module Companion.Types exposing (PhoneToWatch(..))

      import Dict

      type PhoneToWatch
          = PushLabels (Dict.Dict String Int)
      """
    )

    File.write!(
      Path.join(workspace, "protocol/src/Companion/Watch.elm"),
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

    workspace
  end

  defp tmp_workspace! do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "compiler_protocol_check_#{System.unique_integer([:positive])}"
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
      module Companion.Types exposing (PhoneToWatch(..))

      type PhoneToWatch
          = PushLabels (Dict String Int)
      """
    )

    on_exit(fn -> File.rm_rf(workspace) end)
    workspace
  end
end
