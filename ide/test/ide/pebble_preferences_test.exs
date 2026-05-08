defmodule Ide.PebblePreferencesTest do
  use ExUnit.Case, async: false

  alias Ide.InternalPackages
  alias Ide.PebblePreferences

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_pebble_preferences_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "src"))

    elm_json = %{
      "type" => "application",
      "source-directories" => [
        "src",
        InternalPackages.pebble_companion_preferences_elm_src_abs()
      ],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(root, "elm.json"), Jason.encode!(elm_json, pretty: true))

    on_exit(fn -> File.rm_rf(root) end)

    {:ok, root: root}
  end

  test "extracts Slate-like typed controls from a preference schema", %{root: root} do
    write_module(root, """
    module CompanionPreferences exposing (decodeSettings, settings)

    import Pebble.Companion.Preferences as Preferences

    type alias Settings =
        { background : Preferences.Color
        , showDate : Bool
        , units : Units
        }

    type Units
        = Celsius
        | Fahrenheit

    settings : Preferences.Schema Settings
    settings =
        Preferences.schema "Settings" Settings
            |> Preferences.section "Appearance"
                (\\s ->
                    s
                        |> Preferences.field "background" (Preferences.color "Background" Preferences.black)
                        |> Preferences.field "showDate" (Preferences.toggle "Show date" True)
                )
            |> Preferences.section "Behavior"
                (\\s ->
                    s
                        |> Preferences.field "units"
                            (Preferences.choice "Units"
                                [ Preferences.choiceOption Celsius "c" "Celsius"
                                , Preferences.choiceOption Fahrenheit "f" "Fahrenheit"
                                ]
                            )
                )

    decodeSettings : String -> Result Preferences.Error Settings
    decodeSettings =
        Preferences.decodeString settings
    """)

    assert {:ok, schema} = PebblePreferences.extract(root)
    assert schema.title == "Settings"

    assert [
             %{title: "Appearance", fields: [background, show_date]},
             %{title: "Behavior", fields: [units]}
           ] = schema.sections

    assert background.control == %{type: "color", default: "#000000"}
    assert show_date.control == %{type: "toggle", default: true}
    assert units.control.type == "choice"
    assert Enum.map(units.control.options, & &1.value) == ["c", "f"]
  end

  test "extracts numeric, slider, and text controls from a second schema", %{root: root} do
    write_module(root, """
    module CompanionPreferences exposing (settings)

    import Pebble.Companion.Preferences as Preferences

    type alias Settings =
        { name : String
        , refreshMinutes : Float
        , opacity : Float
        }

    settings : Preferences.Schema Settings
    settings =
        Preferences.schema "Advanced" Settings
            |> Preferences.section "General"
                (\\s ->
                    s
                        |> Preferences.field "name" (Preferences.text "Name" "Pebble")
                        |> Preferences.field "refreshMinutes" (Preferences.number "Refresh" 15)
                        |> Preferences.field "opacity"
                            (Preferences.slider "Opacity"
                                { min = 0
                                , max = 1
                                , step = 0.1
                                , default = 0.8
                                }
                            )
                )
    """)

    assert {:ok, schema} = PebblePreferences.extract(root)
    assert [%{fields: [name, refresh, opacity]}] = schema.sections
    assert name.control == %{type: "text", default: "Pebble"}
    assert refresh.control == %{type: "number", default: 15.0}
    assert opacity.control == %{type: "slider", min: 0.0, max: 1.0, step: 0.1, default: 0.8}
  end

  test "renders a static Pebble configuration page" do
    html =
      PebblePreferences.render_html(%{
        title: "Settings",
        sections: [
          %{
            title: "Display",
            fields: [
              %{id: "showDate", label: "Show date", control: %{type: "toggle", default: true}}
            ]
          }
        ]
      })

    assert html =~ "pebblejs://close#"
    assert html =~ "return_to"
    assert html =~ "Show date"
    assert html =~ "\"showDate\""
    assert html =~ "JSON.stringify(values)"
  end

  test "encodes data URLs without raw fragments" do
    data_url =
      PebblePreferences.data_url(%{
        title: "Settings",
        sections: [
          %{
            title: "Display",
            fields: [
              %{id: "showDate", label: "Show date", control: %{type: "toggle", default: true}}
            ]
          }
        ]
      })

    assert String.starts_with?(data_url, "data:text/html;charset=utf-8,")
    refute data_url =~ "#"
    assert data_url =~ "%23f2f2f2"
    assert URI.decode(data_url) =~ "background:#f2f2f2"
  end

  test "enriches configuration fields from explicit companion sendSettings mappings", %{
    root: root
  } do
    write_module(root, """
    module CompanionPreferences exposing (settings)

    import Companion.Types exposing (TutorialColor(..))
    import Pebble.Companion.Preferences as Preferences

    type alias Settings =
        { showDate : Bool
        , backgroundColor : TutorialColor
        }

    settings : Preferences.Schema Settings
    settings =
        Preferences.schema "Settings" Settings
            |> Preferences.section "Display"
                (\\s ->
                    s
                        |> Preferences.field "showDate" (Preferences.toggle "Show date" True)
                        |> Preferences.field "backgroundColor"
                            (Preferences.choice "Background"
                                [ Preferences.choiceOption Black "black" "Black"
                                , Preferences.choiceOption Blue "blue" "Blue"
                                ]
                            )
                )
    """)

    File.write!(Path.join([root, "src", "CompanionApp.elm"]), """
    module CompanionApp exposing (sendSettings)

    import CompanionPreferences
    import Companion.Types exposing (PhoneToWatch(..))

    sendSettings : CompanionPreferences.Settings -> List PhoneToWatch
    sendSettings settings =
        [ SetShowDate settings.showDate
        , SetBackgroundColor settings.backgroundColor
        ]
    """)

    assert {:ok, schema} = PebblePreferences.extract(root)
    fields = Enum.flat_map(schema.sections, & &1.fields)
    show_date = Enum.find(fields, &(&1.id == "showDate"))
    background = Enum.find(fields, &(&1.id == "backgroundColor"))

    assert show_date.control.send_to_watch == "SetShowDate"
    assert background.control.send_to_watch == "SetBackgroundColor"
  end

  defp write_module(root, source) do
    File.write!(Path.join([root, "src", "CompanionPreferences.elm"]), source)
  end
end
