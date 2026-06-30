defmodule IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadataTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadata

  test "public_model keeps Elm init_model screen fields for watch apps" do
    runtime = %{
      model: %{
        "runtime_model" => %{
          "cells" => List.duplicate(0, 16),
          "score" => 0,
          "screenW" => 260,
          "screenH" => 260,
          "displayShape" => %{"ctor" => "Round", "args" => []}
        }
      },
      shell: %{
        "debugger_contract" => %{
          "init_model" => %{
            "cells" => [],
            "score" => 0,
            "screenW" => 144,
            "screenH" => 168,
            "displayShape" => %{"ctor" => "Rectangular", "args" => []}
          }
        }
      }
    }

    assert ModelMetadata.public_model(runtime) == %{
             "cells" => List.duplicate(0, 16),
             "score" => 0,
             "screenW" => 260,
             "screenH" => 260,
             "displayShape" => %{"ctor" => "Round", "args" => []}
           }
  end

  test "public_model still hides companion-only protocol placeholders" do
    runtime = %{model: %{"status" => "idle"}, shell: %{}}

    assert ModelMetadata.public_model(runtime) == %{}
  end

  test "public_model drops undeclared screen fields from companion apps" do
    runtime = %{
      model: %{
        "runtime_model" => %{
          "settings" => %{"ctor" => "Just", "args" => [%{}]},
          "lastLocation" => %{"ctor" => "Nothing"},
          "errors" => [],
          "screenW" => 144,
          "screenH" => 168
        }
      },
      shell: %{
        "debugger_contract" => %{
          "init_model" => %{
            "settings" => %{"ctor" => "Nothing"},
            "lastLocation" => %{"ctor" => "Nothing"},
            "errors" => []
          }
        }
      }
    }

    assert ModelMetadata.public_model(runtime) == %{
             "settings" => %{"ctor" => "Just", "args" => [%{}]},
             "lastLocation" => %{"ctor" => "Nothing"},
             "errors" => []
           }
  end
end
