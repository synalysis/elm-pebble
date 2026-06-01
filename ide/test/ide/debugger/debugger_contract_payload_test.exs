defmodule Ide.Debugger.DebuggerContractPayloadTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompileContract

  test "arithmetic fixture exposes executor-facing introspect fields" do
    assert {:ok, snapshot} =
             CompileContract.analyze_source(
               """
               module Main exposing (main)

               main =
                   1 + 2
               """,
               "Main.elm"
             )

    assert %{"debugger_contract" => payload} = snapshot
    assert payload["module"] == "Main"
    assert is_list(payload["msg_constructors"])
    assert Map.has_key?(payload, "init_model")
    assert is_map(payload["view_tree"])
  end

  test "case-expression fixture exposes update and view branch metadata" do
    assert {:ok, snapshot} =
             CompileContract.analyze_source(
               """
               module Main exposing (main)

               type Msg = Tick | Reset

               main =
                   0
               """,
               "Main.elm"
             )

    payload = snapshot["debugger_contract"]
    assert payload["module"] == "Main"
    assert "Tick" in payload["msg_constructors"]
    assert "Reset" in payload["msg_constructors"]
    assert is_map(payload["msg_constructor_arities"])
    assert is_map(payload["msg_constructor_arg_types"])
  end

  test "app-focus fixture exposes unary msg constructor arg types" do
    source =
      File.read!(
        Path.expand("../../../priv/project_templates/watch_demo_app_focus/src/Main.elm", __DIR__)
      )

    assert {:ok, snapshot} = CompileContract.analyze_source(source, "watch/src/Main.elm")
    payload = snapshot["debugger_contract"]

    assert payload["msg_constructor_arg_types"] == %{"FocusChanged" => "AppFocus.State"}
  end

  test "payload includes update branches list for runtime stepping" do
    assert {:ok, snapshot} =
             CompileContract.analyze_source(
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

    payload = snapshot["debugger_contract"]
    assert is_list(payload["update_case_branches"])
  end
end
