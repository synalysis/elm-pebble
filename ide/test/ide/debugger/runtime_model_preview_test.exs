defmodule Ide.Debugger.RuntimeModelPreviewTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeModelPreview

  test "merge_matching_fields updates only keys that exist on the runtime model" do
    runtime_model = %{"batteryLevel" => 50, "connected" => false}

    merged =
      RuntimeModelPreview.merge_matching_fields(runtime_model, %{
        "batteryLevel" => 88,
        "connected" => true,
        "unknownPreviewKey" => "ignored"
      })

    assert merged == %{"batteryLevel" => 88, "connected" => true}
  end

  test "merge_matching_fields wraps nil fields as Just constructors" do
    runtime_model = %{"timezone" => nil}

    assert RuntimeModelPreview.merge_matching_fields(runtime_model, %{
             "timezone" => "Europe/Berlin"
           }) ==
             %{"timezone" => %{"ctor" => "Just", "args" => ["Europe/Berlin"]}}
  end
end
