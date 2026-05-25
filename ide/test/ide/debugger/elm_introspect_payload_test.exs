defmodule Ide.Debugger.ElmIntrospectPayloadTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ElmIntrospect

  test "arithmetic fixture exposes executor-facing introspect fields" do
    assert {:ok, snapshot} =
             ElmIntrospect.analyze_source(
               """
               module Main exposing (main)

               main =
                   1 + 2
               """,
               "Main.elm"
             )

    assert %{"elm_introspect" => payload} = snapshot
    assert payload["module"] == "Main"
    assert is_list(payload["msg_constructors"])
    assert Map.has_key?(payload, "init_model")
    assert is_map(payload["view_tree"])
  end

  test "case-expression fixture exposes update and view branch metadata" do
    assert {:ok, snapshot} =
             ElmIntrospect.analyze_source(
               """
               module Main exposing (main)

               type Msg = Tick | Reset

               main =
                   0
               """,
               "Main.elm"
             )

    payload = snapshot["elm_introspect"]
    assert payload["module"] == "Main"
    assert "Tick" in payload["msg_constructors"]
    assert "Reset" in payload["msg_constructors"]
    assert is_map(payload["msg_constructor_arities"])
  end

  test "payload includes update branches list for runtime stepping" do
    assert {:ok, snapshot} =
             ElmIntrospect.analyze_source(
               """
               module Main exposing (main)

               type Msg = Inc

               update msg model =
                   model

               main =
                   0
               """,
               "Main.elm"
             )

    payload = snapshot["elm_introspect"]
    assert is_list(payload["update_case_branches"])
  end
end
