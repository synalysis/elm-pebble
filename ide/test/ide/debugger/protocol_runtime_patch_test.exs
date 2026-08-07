defmodule Ide.Debugger.ProtocolRuntimePatchTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ProtocolRuntimePatch

  test "Provide* patch tolerates nil init_model without crashing" do
    introspect = %{
      "init_model" => nil,
      "update_case_branches" => []
    }

    message = %{
      "ctor" => "ProvideWeather",
      "args" => [%{"temperatureC" => 21}]
    }

    assert %{} = ProtocolRuntimePatch.runtime_patch_for_message(introspect, message)
  end

  test "Provide* patch maps ctor to init_model field when present" do
    introspect = %{
      "init_model" => %{"condition" => nil},
      "update_case_branches" => []
    }

    message = %{
      "ctor" => "ProvideCondition",
      "args" => ["Fog"]
    }

    assert ProtocolRuntimePatch.runtime_patch_for_message(introspect, message) == %{
             "condition" => "Fog"
           }
  end
end
