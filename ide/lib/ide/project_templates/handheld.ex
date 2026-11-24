defmodule Ide.ProjectTemplates.Handheld do
  @moduledoc """
  Handheld project templates.

  These stay out of `ProjectTemplates.template_keys/0` so the Pebble PBW and
  preview gates keep compiling watch apps only. New hardware examples are
  another entry in `@examples`.
  """

  alias Ide.InternalPackages
  alias Ide.PebbleToolchain
  alias Ide.ProjectTemplates.Types, as: TemplateTypes

  @starter "handheld-starter"

  @examples [
    {"handheld-demo-display", "Display", "Clear, pixel, line, rectangles, circles, and text."},
    {"handheld-demo-nfc", "NFC", "Start an NFC scan."},
    {"handheld-demo-usb", "USB", "Tap Enter when USB is present."},
    {"handheld-demo-infrared", "Infrared", "Send a short IR pulse train."},
    {"handheld-demo-gpio", "GPIO", "Drive a pin high."},
    {"handheld-demo-radio", "Radio", "GET a URL through the radio."},
    {"handheld-demo-vibes", "Vibes", "Play a short pulse."},
    {"handheld-demo-battery", "Battery", "Read the battery percent."},
    {"handheld-demo-input", "Buttons", "Match a button press."}
  ]

  @spec template_keys() :: [String.t()]
  def template_keys, do: [@starter | Enum.map(@examples, &elem(&1, 0))]

  @spec template?(String.t()) :: boolean()
  def template?(key) when is_binary(key), do: key in template_keys()
  def template?(_), do: false

  @spec source_roots() :: [String.t()]
  def source_roots, do: ["app"]

  @spec default_template() :: String.t()
  def default_template, do: @starter

  @spec picker_categories() :: [TemplateTypes.picker_category()]
  def picker_categories do
    [
      %{
        id: "starter",
        label: "Starter",
        templates: [picker_entry(@starter, "Starter", "Clears the panel and draws a bar.")]
      },
      %{
        id: "api",
        label: "Hardware APIs",
        templates:
          Enum.map(@examples, fn {key, title, description} ->
            picker_entry(key, title, description)
          end)
      }
    ]
  end

  @spec picker_title(String.t()) :: String.t() | nil
  def picker_title(key) do
    picker_categories()
    |> Enum.flat_map(& &1.templates)
    |> Enum.find_value(fn entry -> if entry.key == key, do: entry.title end)
  end

  @spec release_defaults() :: map()
  def release_defaults do
    %{
      "device_family" => "handheld",
      "target_platforms" => Ide.Handheld.Models.ordered_ids()
    }
  end

  @spec seed(String.t(), String.t()) :: :ok | {:error, term()}
  def seed(workspace_path, template) when is_binary(workspace_path) do
    app_root = Path.join(workspace_path, "app")
    main = Path.join(app_root, "src/Main.elm")

    with :ok <- File.mkdir_p(Path.dirname(main)),
         :ok <- File.write(Path.join(app_root, "elm.json"), elm_json()),
         :ok <- File.write(main, main_source(template)) do
      :ok
    end
  end

  defp picker_entry(key, title, description) do
    %{
      key: key,
      title: title,
      description: description,
      target_type: "app",
      has_companion: false,
      screenshot_url: nil
    }
  end

  defp elm_json do
    Jason.encode!(
      %{
        "type" => "application",
        "source-directories" => ["src", InternalPackages.handheld_elm_src_abs()],
        "elm-version" => elm_version(),
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      },
      pretty: true
    )
  end

  defp elm_version do
    case PebbleToolchain.elm_compiler_version() do
      {:ok, version} when is_binary(version) and version != "" -> version
      _ -> "0.19.1"
    end
  end

  defp main_source("handheld-starter") do
    program(
      ["import Handheld.Color as Color", "import Handheld.Ui as Ui"],
      """
      init : Platform.LaunchContext -> ( Model, Cmd msg )
      init context =
          ( { width = context.screen.width, height = context.screen.height }
          , Cmd.none
          )
      """,
      "update _ model =\n    ( model, Cmd.none )\n",
      model: "{ width : Int, height : Int }",
      view: """
      view model =
          Cmd.batch
              [ Ui.clear Color.black
              , Ui.fill
                  { x = 0
                  , y = model.height // 2
                  , width = model.width
                  , height = 8
                  }
                  Color.white
              ]
      """
    )
  end

  defp main_source("handheld-demo-display") do
    program(
      ["import Handheld.Color as Color", "import Handheld.Ui as Ui"],
      """
      init : Platform.LaunchContext -> ( Model, Cmd msg )
      init context =
          ( { width = context.screen.width, height = context.screen.height }
          , Cmd.none
          )
      """,
      "update _ model =\n    ( model, Cmd.none )\n",
      model: "{ width : Int, height : Int }",
      view: """
      view model =
          Cmd.batch
              [ Ui.clear Color.black
              , Ui.fill { x = 0, y = 0, width = model.width, height = 4 } Color.white
              , Ui.rect { x = 4, y = 10, width = 28, height = 18 } Color.white
              , Ui.pixel { x = 10, y = 16 } Color.white
              , Ui.line { x = 36, y = 10 } { x = 56, y = 28 } Color.white
              , Ui.circle { x = 74, y = 19 } 9 Color.white
              , Ui.fillCircle { x = 100, y = 19 } 7 Color.white
              , Ui.text { x = 4, y = model.height - 14 } "Display" Color.white
              ]
      """
    )
  end

  defp main_source("handheld-demo-nfc") do
    program(
      ["import Handheld.Nfc as Nfc"],
      """
      type Msg
          = TagFound String


      init _ =
          ( {}
          , Nfc.scan
          )
      """,
      """
      update msg model =
          case msg of
              TagFound _ ->
                  ( model, Nfc.read )
      """,
      msg: "Msg",
      subscriptions: """
      subscriptions _ =
          Nfc.onTag TagFound
      """
    )
  end

  defp main_source("handheld-demo-usb") do
    program(
      ["import Handheld.Device as Device exposing (Module(..))", "import Handheld.Usb as Usb"],
      """
      type Msg
          = UsbReady Bool


      init _ =
          ( {}
          , Device.ready Usb UsbReady
          )
      """,
      """
      update msg model =
          case msg of
              UsbReady True ->
                  ( model, Usb.tap Usb.enter )

              UsbReady False ->
                  ( model, Cmd.none )
      """,
      msg: "Msg"
    )
  end

  defp main_source("handheld-demo-infrared") do
    command_program(["import Handheld.Infrared as Infrared"], "Infrared.send 16")
  end

  defp main_source("handheld-demo-gpio") do
    command_program(
      ["import Handheld.Gpio as Gpio exposing (Level(..))"],
      "Gpio.write 1 High"
    )
  end

  defp main_source("handheld-demo-radio") do
    command_program(
      ["import Handheld.Radio as Radio"],
      "Radio.get \"http://example.com\""
    )
  end

  defp main_source("handheld-demo-vibes") do
    command_program(["import Handheld.Vibes as Vibes"], "Vibes.shortPulse")
  end

  defp main_source("handheld-demo-battery") do
    program(
      ["import Handheld.Battery as Battery", "import Handheld.Color as Color", "import Handheld.Ui as Ui"],
      """
      type Msg
          = Level Int


      init _ =
          ( { level = 0 }
          , Battery.level Level
          )
      """,
      """
      update msg model =
          case msg of
              Level level ->
                  ( { model | level = level }
                  , Ui.fill { x = 0, y = 0, width = level, height = 4 } Color.white
                  )
      """,
      model: "{ level : Int }",
      msg: "Msg"
    )
  end

  defp main_source("handheld-demo-input") do
    program(
      [
        "import Handheld.Color as Color",
        "import Handheld.Input as Input exposing (Button(..))",
        "import Handheld.Ui as Ui"
      ],
      """
      type Msg
          = Pressed Button


      init _ =
          ( { button = Select }
          , Cmd.none
          )
      """,
      """
      update msg model =
          case msg of
              Pressed button ->
                  ( { model | button = button }
                  , Cmd.none
                  )
      """,
      model: "{ button : Button }",
      msg: "Msg",
      subscriptions: """
      subscriptions _ =
          Input.presses Pressed
      """,
      view: """
      view model =
          Ui.fill
              { x = 0
              , y = 0
              , width = 12
              , height =
                  case model.button of
                      Up ->
                          4

                      Down ->
                          8

                      _ ->
                          2
              }
              Color.white
      """
    )
  end

  defp main_source(_), do: main_source("handheld-starter")

  defp command_program(imports, expr) do
    program(
      imports,
      """
      init _ =
          ( {}
          , #{expr}
          )
      """,
      "update _ model =\n    ( model, Cmd.none )\n"
    )
  end

  defp view_block(msg, nil) do
    """
    view : Model -> Cmd #{msg}
    view _ =
        Cmd.none
    """
  end

  defp view_block(msg, source) when is_binary(source) do
    """
    view : Model -> Cmd #{msg}
    #{String.trim(source)}
    """
  end

  defp program(imports, init_block, update_block, opts \\ []) do
    model = Keyword.get(opts, :model, "{}")
    msg = Keyword.get(opts, :msg, "Never")
    msg_decl = if msg == "Never", do: "", else: ""

    subscriptions =
      Keyword.get(opts, :subscriptions, """
      subscriptions : Model -> Sub #{msg}
      subscriptions _ =
          Sub.none
      """)

    """
    module Main exposing (main)

    import Handheld.Platform as Platform
    import Json.Decode
    #{Enum.join(imports, "\n")}


    type alias Model =
        #{model}

    #{msg_decl}

    #{String.trim(init_block)}


    #{String.trim(update_block)}


    #{String.trim(subscriptions)}


    #{view_block(msg, Keyword.get(opts, :view))}


    main : Program Json.Decode.Value Model #{msg}
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end
end
