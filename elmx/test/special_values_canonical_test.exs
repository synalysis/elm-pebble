defmodule Elmx.SpecialValuesCanonicalTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.SpecialValues

  test "canonical_target maps import shorthands to Platform modules" do
    assert SpecialValues.canonical_target("Cmd.none") == "Platform.Cmd.none"
    assert SpecialValues.canonical_target("Cmd.batch") == "Platform.Cmd.batch"
    assert SpecialValues.canonical_target("Sub.none") == "Platform.Sub.none"
    assert SpecialValues.canonical_target("Pebble.Cmd.none") == "Pebble.Cmd.none"
  end

  test "rewrite accepts Cmd.none shorthand via canonicalization" do
    assert {:ok, %{op: :cmd_none}} = SpecialValues.rewrite("Cmd.none", [])
    assert {:ok, %{op: :cmd_none}} = SpecialValues.rewrite("Platform.Cmd.none", [])
  end

  test "Platform.Cmd time helpers rewrite after Cmd import canonicalization" do
    to_msg = %{op: :constructor_call, target: "CurrentTimeString", args: []}

    assert {:ok, %{op: :runtime_call, function: "elmx_time_current_time_string"}} =
             SpecialValues.rewrite("Cmd.getCurrentTimeString", [to_msg])

    assert {:ok, %{op: :runtime_call, function: "elmx_time_current_time_string"}} =
             SpecialValues.rewrite("Platform.Cmd.getCurrentTimeString", [to_msg])

    assert {:ok, %{op: :runtime_call, function: "elmx_platform_application"}} =
             SpecialValues.rewrite("Platform.application", [])
  end
end
