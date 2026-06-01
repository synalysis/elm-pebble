defmodule Elmx.ConstructorEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ConstructorEmit
  alias Elmx.Backend.ConstructorLookup
  alias ElmEx.IR

  defp lookup!(modules) do
    %IR{modules: modules, diagnostics: []}
    |> ConstructorLookup.from_ir()
  end

  test "color constructors delegate to SpecialValues via qualified IR target" do
    lookup =
      lookup!([
        %{
          name: "Pebble.Ui.Color",
          declarations: [],
          unions: %{
            "Color" => %{
              tags: %{"white" => 1},
              payload_kinds: %{"white" => :none}
            }
          }
        }
      ])

    entry = ConstructorLookup.resolve(lookup, "white", "Main")
    assert {:ok, %{op: :runtime_call, function: "elmx_ui_named_color"}} = ConstructorEmit.rewrite(entry)
  end

  test "resource constructors emit union tag from IR" do
    lookup =
      lookup!([
        %{
          name: "Pebble.Ui.Resources",
          declarations: [],
          unions: %{
            "Font" => %{
              tags: %{"DefaultFont" => 3},
              payload_kinds: %{"DefaultFont" => :none}
            }
          }
        }
      ])

    entry = ConstructorLookup.resolve(lookup, "DefaultFont", "Main")
    assert {:ok, %{op: :int_literal, value: 3}} = ConstructorEmit.rewrite(entry)
  end

  test "Label union constructors emit constructor name string" do
    lookup =
      lookup!([
        %{
          name: "Pebble.Ui",
          declarations: [],
          unions: %{
            "Label" => %{
              tags: %{"WaitingForCompanion" => 1},
              payload_kinds: %{"WaitingForCompanion" => :none}
            }
          }
        }
      ])

    entry = ConstructorLookup.resolve(lookup, "WaitingForCompanion", "Main")
    assert {:ok, %{op: :string_literal, value: "WaitingForCompanion"}} = ConstructorEmit.rewrite(entry)
  end
end
