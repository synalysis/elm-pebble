defmodule Ide.Debugger.ProtocolWatchTagValueTest do
  use ExUnit.Case, async: true

  alias Ide.CompanionProtocolGenerator
  alias Ide.Debugger.ProtocolEvents.CmdCall.Core

  @types_path Path.join([
                "priv",
                "project_templates",
                "companion_demo_protocol_matrix",
                "protocol",
                "src",
                "Companion",
                "Types.elm"
              ])

  setup do
    types = File.read!(@types_path)
    {:ok, schema} = CompanionProtocolGenerator.schema_from_source(types)
    {:ok, schema: schema}
  end

  test "decodes tag-only Ping from companionSend wire", %{schema: schema} do
    ping = Enum.find(schema.watch_to_phone, &(&1.name == "Ping"))

    assert {"Ping", %{"ctor" => "Ping", "args" => []}} =
             Core.normalize_protocol_message_value_from_schema(
               schema,
               :watch_to_phone,
               %{"tag" => ping.tag, "value" => 0},
               "tag:#{ping.tag}"
             )
  end

  test "decodes SendColor enum from companionSend wire", %{schema: schema} do
    send_color = Enum.find(schema.watch_to_phone, &(&1.name == "SendColor"))
    red_wire = CompanionProtocolGenerator.wire_code_base()

    assert {"SendColor Red", %{"ctor" => "SendColor", "args" => [%{"ctor" => "Red", "args" => []}]}} =
             Core.normalize_protocol_message_value_from_schema(
               schema,
               :watch_to_phone,
               %{"tag" => send_color.tag, "value" => red_wire},
               "tag:#{send_color.tag}"
             )
  end

  test "decodes SendMeasure union variant tag only (payload int not on wire)", %{schema: schema} do
    send_measure = Enum.find(schema.watch_to_phone, &(&1.name == "SendMeasure"))
    liters_tag = CompanionProtocolGenerator.wire_code_base()

    assert {"SendMeasure Liters 0",
            %{"ctor" => "SendMeasure", "args" => [%{"ctor" => "Liters", "args" => [0]}]}} =
             Core.normalize_protocol_message_value_from_schema(
               schema,
               :watch_to_phone,
               %{"tag" => send_measure.tag, "value" => liters_tag},
               "tag:#{send_measure.tag}"
             )
  end

  test "cannot decode composite record/list watch sends from single int wire", %{schema: schema} do
    send_point = Enum.find(schema.watch_to_phone, &(&1.name == "SendPoint"))
    send_counts = Enum.find(schema.watch_to_phone, &(&1.name == "SendCounts"))

    assert :error =
             Core.normalize_protocol_message_value_from_schema(
               schema,
               :watch_to_phone,
               %{"tag" => send_point.tag, "value" => 0},
               "tag:#{send_point.tag}"
             )

    assert :error =
             Core.normalize_protocol_message_value_from_schema(
               schema,
               :watch_to_phone,
               %{"tag" => send_counts.tag, "value" => 0},
               "tag:#{send_counts.tag}"
             )
  end
end
