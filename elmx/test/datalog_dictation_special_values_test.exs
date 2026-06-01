defmodule Elmx.DatalogDictationSpecialValuesTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Followups
  alias Elmx.Runtime.MessageDecode
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues

  test "Pebble.DataLog.tag rewrites to runtime tag ctor" do
    assert {:ok, %{op: :runtime_call, function: "elmx_datalog_tag", args: [arg]}} =
             SpecialValues.rewrite("Pebble.DataLog.tag", [%{op: :int_literal, value: 9001}])

    assert arg.value == 9001
  end

  test "Pebble.Dictation.start rewrites to runtime cmd" do
    assert {:ok, %{op: :runtime_call, function: "elmx_dictation_start", args: []}} =
             SpecialValues.rewrite("Pebble.Dictation.start", [])
  end

  test "dictation start produces status and result followups" do
    cmd = Pebble.runtime_dispatch("elmx_dictation_start", [])
    messages = cmd |> Followups.from_commands() |> Enum.map(& &1["message"])

    assert "DictationStatusChanged" in messages
    assert "DictationFinished" in messages

    finished =
      Enum.find(cmd["commands"], fn c -> c["message"] == "DictationFinished" end)

    assert {:DictationFinished, {:Ok, "Hello"}} =
             MessageDecode.decode("DictationFinished", finished["message_value"])
  end

  test "dictation stop produces cancelled result followup" do
    cmd = Pebble.runtime_dispatch("elmx_dictation_stop", [])
    assert [%{"message" => "DictationFinished"}] = Followups.from_commands(cmd)

    assert {:DictationFinished, {:Err, :Cancelled}} =
             MessageDecode.decode(cmd["message"], cmd["message_value"])
  end

  test "runtime datalog tag and log commands" do
    tag = Pebble.runtime_dispatch("elmx_datalog_tag", [9001])
    assert tag == %{"ctor" => "Tag", "args" => [9001]}

    cmd = Pebble.runtime_dispatch("elmx_datalog_log_int32", [tag, 3])
    assert cmd["kind"] == "cmd.data_log.int32"
    assert cmd["tag"] == 9001
    assert cmd["value"] == 3

    bytes_cmd = Pebble.runtime_dispatch("elmx_datalog_log_bytes", [tag, [1, 2, 3]])
    assert bytes_cmd["kind"] == "cmd.data_log.bytes"
    assert bytes_cmd["bytes"] == [1, 2, 3]
  end

  test "Cmd.data_log helpers accept bare tag integers" do
    assert %{"kind" => "cmd.data_log.int32", "tag" => 42, "value" => 7} =
             Cmd.data_log_int32(42, 7)
  end
end
