defmodule Ide.Debugger.RuntimeModelNormalizeTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeModelNormalize

  test "init_model hydrates init_model from introspect shell" do
    model = %{
      "elm_introspect" => %{
        "init_model" => %{"batteryLevel" => %{"ctor" => "Just", "args" => [88]}}
      }
    }

    assert RuntimeModelNormalize.init_model(model) == %{
             "batteryLevel" => %{"ctor" => "Just", "args" => [88]}
           }
  end

  test "patch_values normalizes runtime_model patch against init model shape" do
    model = %{
      "runtime_model" => %{"count" => %{"ctor" => "Just", "args" => [1]}},
      "elm_introspect" => %{"init_model" => %{"count" => %{"ctor" => "Just", "args" => [0]}}}
    }

    patch = %{"runtime_model" => %{"count" => 2}}

    assert RuntimeModelNormalize.patch_values(model, patch) == %{
             "runtime_model" => %{"count" => %{"ctor" => "Just", "args" => [2]}}
           }
  end
end
