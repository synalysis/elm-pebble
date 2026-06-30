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

  test "against_introspect keeps evaluated fields declared as parser calls in init_model" do
    model = %{
      "debugger_contract" => %{
        "init_model" => %{
          "screenW" => 144,
          "player" => %{"$call" => "Pokemon.playerFromSpecies", "$args" => []},
          "layout" => %{"$call" => "Render.layoutFor", "$args" => [%{"$ctor" => "Rectangular"}]}
        }
      }
    }

    runtime_model = %{
      "screenW" => 144,
      "player" => %{"displayName" => "Pikachu", "species" => %{"ctor" => "Pikachu", "args" => []}},
      "layout" => %{"boxX" => 10}
    }

    normalized = RuntimeModelNormalize.against_introspect(runtime_model, model)

    assert normalized["player"]["displayName"] == "Pikachu"
    assert normalized["layout"]["boxX"] == 10
  end

  test "against_introspect removes runtime fields absent from init_model" do
    model = %{
      "debugger_contract" => %{
        "init_model" => %{"count" => 0, "enabled" => false}
      }
    }

    runtime_model = %{"count" => 1, "enabled" => true, "clock_style_24h" => true}

    assert RuntimeModelNormalize.against_introspect(runtime_model, model) == %{
             "count" => 1,
             "enabled" => true
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

  test "patch_values keeps prior runtime_model fields when patch only updates one key" do
    model = %{
      "runtime_model" => %{"screenW" => 144, "screenH" => 168, "now" => %{"ctor" => "Nothing", "args" => []}},
      "debugger_contract" => %{
        "init_model" => %{
          "screenW" => 144,
          "screenH" => 168,
          "now" => %{"ctor" => "Nothing", "args" => []}
        }
      }
    }

    patch = %{
      "runtime_model" => %{
        "now" => %{
          "ctor" => "Just",
          "args" => [%{"hour" => 15, "minute" => 6}]
        }
      }
    }

    assert %{"runtime_model" => normalized} = RuntimeModelNormalize.patch_values(model, patch)
    assert normalized["screenW"] == 144
    assert normalized["screenH"] == 168
    assert get_in(normalized, ["now", "ctor"]) == "Just"
  end
end
