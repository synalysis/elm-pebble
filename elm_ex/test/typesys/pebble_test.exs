defmodule ElmEx.Typesys.PebbleTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{Bridge, Module, Project}
  alias ElmEx.Typesys.{Check, Env, Kernel, Parser}

  test "kernel installs declared Pebble watch schemes" do
    env = Kernel.install(Env.new())

    for name <- [
          "Pebble.Platform.watchface",
          "Pebble.Platform.application",
          "Pebble.Platform.worker",
          "Pebble.Events.onMinuteChange",
          "Pebble.Cmd.timerAfter",
          "Pebble.Cmd.getCurrentDateTime",
          "Pebble.Time.currentDateTime",
          "Pebble.Storage.readInt",
          "Pebble.Ui.toUiNode",
          "Pebble.Ui.clear",
          "Pebble.Ui.rect",
          "Json.Decode.array",
          "Pebble.Ui.Color.white",
          "Pebble.Button.onPress",
          "Pebble.Alarm.toPosix"
        ] do
      assert Env.lookup_value(env, name), "missing kernel value #{name}"
    end

    assert Env.lookup_alias(env, "Pebble.Platform.LaunchContext")
    assert Env.lookup_ctor(env, "Pebble.Platform.Round")
    assert Env.lookup_ctor(env, "Pebble.Button.Select")

    for name <- [
          "Pebble.Health.sumToday",
          "Pebble.Health.onEvent",
          "Pebble.Touch.onTap",
          "Pebble.Compass.current",
          "Pebble.Accel.onData",
          "Pebble.Speaker.playNotes",
          "Pebble.Dictation.onResult",
          "Pebble.Companion.Weather.current",
          "Pebble.Companion.Command.command",
          "Companion.Watch.sendWatchToPhone",
          "Companion.Watch.onPhoneToWatch",
          "Pebble.Ui.Resources.DefaultFont",
          "Pebble.Ui.Resources.fontInfo",
          "Pebble.Ui.Resources.staticVectorInfo",
          "Pebble.Game.Collision.rectRect",
          "Pebble.Internal.Companion.companionSend"
        ] do
      assert Env.lookup_value(env, name), "missing kernel value #{name}"
    end

    assert Env.lookup_alias(env, "Pebble.Ui.Resources.FontInfo")
    assert Env.lookup_alias(env, "Pebble.Ui.Font")

    assert {:ok, _} =
             ElmEx.Typesys.Solve.unify(
               env,
               ElmEx.Typesys.Type.named("Pebble.Ui.Font"),
               ElmEx.Typesys.Type.named("Pebble.Ui.Resources.Font"),
               []
             )

    assert Env.lookup_ctor(env, "Pebble.Health.StepCount")
    assert Env.lookup_ctor(env, "Pebble.WatchInfo.PebbleTime")
  end

  test "watchface program config type parses" do
    src =
      "{ init : Pebble.Platform.LaunchContext -> (model, Cmd msg), update : msg -> model -> (model, Cmd msg), view : model -> view, subscriptions : model -> Sub msg } -> Program Value model msg"

    assert {:ok, {:fun, {:record, fields, nil}, {:named, "Program", _}}} = Parser.parse(src)
    assert Map.has_key?(fields, "init")
    assert Map.has_key?(fields, "view")
  end

  test "Pebble.Ui.text accepts the one-argument string shorthand" do
    source = """
    module Main exposing (label)

    import Pebble.Ui as Ui

    label : Pebble.Ui.RenderOp
    label =
        Ui.text "ok"
    """

    assert load_source_errors(source) == []
  end

  test "Ui.text field access prefers the one-argument shorthand" do
    source = """
    module Main exposing (view)

    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { shown : String }

    view : Model -> Pebble.Ui.UiNode
    view model =
        Ui.toUiNode [ Ui.clear Color.white, Ui.text model.shown ]
    """

    assert load_source_errors(source) == []
  end

  test "package Pebble.Ui annotation keeps the text shorthand" do
    project = %Project{
      project_dir: "/tmp/typesys-pebble-text-alts",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [
        %Module{
          name: "Pebble.Ui",
          path: "/tmp/typesys-pebble-text-alts/packages/Pebble/Ui.elm",
          imports: [],
          declarations: [
            %{
              kind: :function_signature,
              name: "text",
              type:
                "Pebble.Ui.Font -> Pebble.Ui.TextOptions -> Pebble.Ui.Rect -> String -> Pebble.Ui.RenderOp"
            }
          ]
        }
      ],
      diagnostics: []
    }

    env = Env.build(project)
    schemes = Env.lookup_value_schemes(env, "Pebble.Ui.text")
    assert length(schemes) >= 2
  end

  test "Pebble.Platform as PebblePlatform resolves worker" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd
    import Pebble.Ui as Ui
    import Platform.Sub

    main =
        PebblePlatform.worker
            { init = \\_ -> ( 0, Cmd.none )
            , update = \\_ model -> ( model, Cmd.none )
            , view = \\_ -> Ui.toUiNode []
            , subscriptions = \\_ -> Sub.none
            }
    """

    errors = load_source_errors(source)

    refute Enum.any?(errors, fn d ->
             (Map.get(d, :code) || Map.get(d, "code")) == "unbound_value"
           end),
           inspect(errors)
  end

  test "Pebble.Platform alias worker accepts a view field" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    main =
        Platform.worker
            { init = \\_ -> ( 0, Platform.Cmd.none )
            , update = \\_ model -> ( model, Platform.Cmd.none )
            , view = \\_ -> Ui.toUiNode []
            , subscriptions = \\_ -> Platform.Sub.none
            }
    """

    errors = load_source_errors(source)

    refute Enum.any?(errors, fn d ->
             msg = Map.get(d, :message) || Map.get(d, "message") || ""
             String.contains?(to_string(msg), "extra fields: view")
           end),
           inspect(errors)
  end

  test "accepts displayShapeIsRound on LaunchContext.screen.shape" do
    project =
      project([
        function("Main", "roundScreen", "Pebble.Platform.LaunchContext -> Bool", ["ctx"], %{
          op: :qualified_call,
          target: "Pebble.Platform.displayShapeIsRound",
          args: [
            %{
              op: :field_access,
              field: "shape",
              arg: %{
                op: :field_access,
                field: "screen",
                arg: %{op: :var, name: "ctx"}
              }
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "accepts Events.onMinuteChange and Cmd.timerAfter" do
    project =
      project([
        %{
          kind: :union,
          name: "Msg",
          constructors: [%{name: "Tick", arg: "Int"}],
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "subs", "Sub Msg", [], %{
          op: :qualified_call,
          target: "Pebble.Events.onMinuteChange",
          args: [%{op: :var, name: "Tick"}]
        }),
        function("Main", "pulse", "Cmd Msg", [], %{
          op: :qualified_call,
          target: "Pebble.Cmd.timerAfter",
          args: [%{op: :int_literal, value: 1000}]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "accepts annotated Ui.rect helper used by indexedMap" do
    project =
      project([
        function("Main", "cellOp", "Int -> Int -> Pebble.Ui.RenderOp", ["i", "_n"], %{
          op: :qualified_call,
          target: "Pebble.Ui.rect",
          args: [
            %{
              op: :record_literal,
              fields: [
                %{
                  name: "x",
                  expr: %{
                    op: :call,
                    name: "*",
                    args: [%{op: :var, name: "i"}, %{op: :int_literal, value: 4}]
                  }
                },
                %{name: "y", expr: %{op: :int_literal, value: 0}},
                %{name: "w", expr: %{op: :int_literal, value: 2}},
                %{name: "h", expr: %{op: :int_literal, value: 2}}
              ]
            },
            %{op: :var, name: "Pebble.Ui.Color.black"}
          ]
        })
      ])

    {_project, diags} = Check.run(project)

    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"])), inspect(diags)
  end

  test "accepts a minimal watchface-shaped program" do
    project =
      project([
        %{
          kind: :type_alias,
          name: "Model",
          fields: [],
          field_types: %{},
          alias_type: "{}",
          span: %{start_line: 1, end_line: 1}
        },
        %{
          kind: :union,
          name: "Msg",
          constructors: [%{name: "NoOp"}],
          span: %{start_line: 2, end_line: 2}
        },
        function(
          "Main",
          "init",
          "Pebble.Platform.LaunchContext -> (Model, Cmd Msg)",
          ["_ctx"],
          %{
            op: :tuple2,
            left: %{op: :record_literal, fields: []},
            right: %{op: :var, name: "Cmd.none"}
          }
        ),
        function("Main", "update", "Msg -> Model -> (Model, Cmd Msg)", ["_msg", "model"], %{
          op: :tuple2,
          left: %{op: :var, name: "model"},
          right: %{op: :var, name: "Cmd.none"}
        }),
        function("Main", "view", "Model -> Pebble.Ui.UiNode", ["_model"], %{
          op: :qualified_call,
          target: "Pebble.Ui.toUiNode",
          args: [
            %{
              op: :list_literal,
              items: [
                %{
                  op: :qualified_call,
                  target: "Pebble.Ui.clear",
                  args: [%{op: :var, name: "Pebble.Ui.Color.white"}]
                }
              ]
            }
          ]
        }),
        function("Main", "subscriptions", "Model -> Sub Msg", ["_model"], %{
          op: :var,
          name: "Sub.none"
        }),
        function("Main", "main", "Program Value Model Msg", [], %{
          op: :qualified_call,
          target: "Pebble.Platform.watchface",
          args: [
            %{
              op: :record_literal,
              fields: [
                %{name: "init", expr: %{op: :var, name: "init"}},
                %{name: "update", expr: %{op: :var, name: "update"}},
                %{name: "view", expr: %{op: :var, name: "view"}},
                %{name: "subscriptions", expr: %{op: :var, name: "subscriptions"}}
              ]
            }
          ]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "accepts Health.sumToday and Compass.current" do
    project =
      project([
        %{
          kind: :union,
          name: "Msg",
          constructors: [%{name: "NoOp"}],
          span: %{start_line: 1, end_line: 1}
        },
        function("Main", "gotSteps", "Int -> Msg", ["_n"], %{
          op: :constructor_call,
          target: "NoOp",
          args: []
        }),
        function(
          "Main",
          "gotHeading",
          "Result Pebble.Compass.Error Pebble.Compass.Heading -> Msg",
          ["_r"],
          %{
            op: :constructor_call,
            target: "NoOp",
            args: []
          }
        ),
        function("Main", "steps", "Cmd Msg", [], %{
          op: :qualified_call,
          target: "Pebble.Health.sumToday",
          args: [
            %{op: :var, name: "Pebble.Health.StepCount"},
            %{op: :var, name: "gotSteps"}
          ]
        }),
        function("Main", "heading", "Cmd Msg", [], %{
          op: :qualified_call,
          target: "Pebble.Compass.current",
          args: [%{op: :var, name: "gotHeading"}]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "accepts companion Weather.current" do
    project =
      project([
        %{
          kind: :union,
          name: "Msg",
          constructors: [%{name: "NoOp"}],
          span: %{start_line: 1, end_line: 1}
        },
        function(
          "Main",
          "gotWeather",
          "Result String Pebble.Companion.Weather.WeatherInfo -> Msg",
          ["_r"],
          %{
            op: :constructor_call,
            target: "NoOp",
            args: []
          }
        ),
        function("Main", "fetch", "Cmd Msg", [], %{
          op: :qualified_call,
          target: "Pebble.Companion.Weather.current",
          args: [%{op: :var, name: "gotWeather"}]
        })
      ])

    {_project, diags} = Check.run(project)
    refute Enum.any?(diags, &(&1.code in ["type_mismatch", "unbound_value"]))
  end

  test "Pebble.Ui.Font and Pebble.Ui.Resources.Font unify in app code" do
    errors =
      load_source_errors("""
      module Main exposing (go)

      import Pebble.Ui as Ui
      import Pebble.Ui.Resources as Resources

      go : Ui.Font -> Resources.Font
      go font =
          font
      """)

    assert errors == [], inspect(errors)
  end

  test "watchface_minimal template is accepted by typesys" do
    source =
      File.read!(
        Path.expand("../../../ide/priv/project_templates/watchface_minimal/src/Main.elm", __DIR__)
      )

    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-ex-typesys-watchface-minimal-#{System.unique_integer([:positive])}"
      )

    src = Path.join(dir, "src")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "Main.elm"), source)

    File.write!(Path.join(dir, "elm.json"), """
    {
      "type": "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": { "elm/core": "1.0.5", "elm/json": "1.1.3" },
        "indirect": {}
      },
      "test-dependencies": { "direct": {}, "indirect": {} }
    }
    """)

    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, project} = Bridge.load_project(dir, lowerer_diagnostics: false)

    errors =
      (project.diagnostics || [])
      |> Enum.filter(&(Map.get(&1, :severity) == "error" or Map.get(&1, "severity") == "error"))
      |> Enum.filter(fn d ->
        source = Map.get(d, :source) || Map.get(d, "source")
        source == "elm_ex/typesys"
      end)

    assert errors == [], inspect(errors)
  end

  @tag timeout: 180_000
  test "all project templates are accepted by typesys" do
    root = Path.expand("../../../ide/priv/project_templates", __DIR__)

    names =
      root
      |> File.ls!()
      |> Enum.filter(&File.exists?(Path.join([root, &1, "src", "Main.elm"])))
      |> Enum.sort()

    assert names != []

    for name <- names do
      errors = load_template_errors(name)
      assert errors == [], "#{name}: #{inspect(errors)}"
    end
  end

  test "record update of a field access and a trailing underscore name typecheck" do
    source = """
    module Main exposing (main)

    type alias Extras =
        { flag : Bool }


    type alias Model =
        { extras : Extras }


    type alias Row =
        { name : String }


    item_ : String -> Row
    item_ name =
        { name = name }


    shadow : List Row -> List Row
    shadow rows =
        List.map (\\item_ -> item_) rows


    bump : Model -> Model
    bump model =
        let
            extras =
                { model.extras | flag = True }
        in
        { model | extras = extras }


    rows : List Row
    rows =
        [ item_ "Ping" ]


    main : Model
    main =
        bump { extras = { flag = False } }
    """

    errors = load_source_errors(source)
    assert errors == [], inspect(errors)
  end

  test "overlays generated Resources ctors from manifests and strips them after check" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-ex-typesys-overlay-#{System.unique_integer([:positive])}"
      )

    src = Path.join(dir, "src")
    File.mkdir_p!(src)
    File.mkdir_p!(Path.join(dir, "resources"))

    File.write!(Path.join(src, "Main.elm"), """
    module Main exposing (mark)

    import Pebble.Ui.Resources as Resources


    mark : Resources.StaticBitmap
    mark =
        Resources.BitmapStaticHero
    """)

    File.write!(Path.join(dir, "resources/bitmaps.json"), """
    {
      "schema_version": 1,
      "entries": [
        {"id": "bitmap_hero", "ctor": "Hero"}
      ]
    }
    """)

    File.write!(Path.join(dir, "elm.json"), """
    {
      "type": "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": { "elm/core": "1.0.5", "elm/json": "1.1.3" },
        "indirect": {}
      },
      "test-dependencies": { "direct": {}, "indirect": {} }
    }
    """)

    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, project} = Bridge.load_project(dir, lowerer_diagnostics: false)

    errors =
      (project.diagnostics || [])
      |> Enum.filter(&(Map.get(&1, :severity) == "error" or Map.get(&1, "severity") == "error"))
      |> Enum.filter(fn d ->
        (Map.get(d, :source) || Map.get(d, "source")) == "elm_ex/typesys"
      end)

    assert errors == [], inspect(errors)
    refute Enum.any?(project.modules, &(&1.name == "Pebble.Ui.Resources"))
  end

  test "generated Resource ctors resolve after package-module collision mangling" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-ex-typesys-overlay-collide-#{System.unique_integer([:positive])}"
      )

    src = Path.join(dir, "src")
    vendor = Path.join(dir, "vendor")
    pkg = Path.join(dir, "packages/elm-pebble/elm-watch/src")
    File.mkdir_p!(src)
    File.mkdir_p!(Path.join(vendor, "Pebble/Ui"))
    File.mkdir_p!(Path.join(pkg, "Pebble/Ui"))
    File.mkdir_p!(Path.join(dir, "resources"))

    stub = """
    module Pebble.Ui.Resources exposing (StaticVector(..), NoStaticVector)

    type StaticVector
        = NoStaticVector
    """

    File.write!(Path.join(vendor, "Pebble/Ui/Resources.elm"), stub)
    File.write!(Path.join(pkg, "Pebble/Ui/Resources.elm"), stub)

    File.write!(Path.join(src, "Main.elm"), """
    module Main exposing (mark)

    import Pebble.Ui.Resources as Resources


    mark : Resources.StaticVector
    mark =
        Resources.VectorStaticTangramBird
    """)

    File.write!(Path.join(dir, "resources/vectors.json"), """
    {
      "schema_version": 1,
      "entries": [
        {"id": "vector_bird", "ctor": "VectorStaticTangramBird"}
      ]
    }
    """)

    File.write!(Path.join(dir, "elm.json"), """
    {
      "type": "application",
      "source-directories": ["src", "vendor", "packages/elm-pebble/elm-watch/src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": { "elm/core": "1.0.5", "elm/json": "1.1.3" },
        "indirect": {}
      },
      "test-dependencies": { "direct": {}, "indirect": {} }
    }
    """)

    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, project} = Bridge.load_project(dir, lowerer_diagnostics: false)

    errors =
      (project.diagnostics || [])
      |> Enum.filter(&(Map.get(&1, :severity) == "error" or Map.get(&1, "severity") == "error"))
      |> Enum.filter(fn d ->
        (Map.get(d, :source) || Map.get(d, "source")) == "elm_ex/typesys"
      end)

    assert errors == [], inspect(errors)
  end

  test "overlays Companion.Types from the bundled protocol and strips it after check" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-ex-typesys-types-overlay-#{System.unique_integer([:positive])}"
      )

    src = Path.join(dir, "src")
    File.mkdir_p!(src)

    File.write!(Path.join(src, "Main.elm"), """
    module Main exposing (mark)

    import Companion.Types exposing (Location(..), WatchToPhone(..))


    mark : WatchToPhone
    mark =
        RequestWeather Berlin
    """)

    File.write!(Path.join(dir, "elm.json"), """
    {
      "type": "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": { "elm/core": "1.0.5", "elm/json": "1.1.3" },
        "indirect": {}
      },
      "test-dependencies": { "direct": {}, "indirect": {} }
    }
    """)

    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, project} = Bridge.load_project(dir, lowerer_diagnostics: false)

    errors =
      (project.diagnostics || [])
      |> Enum.filter(&(Map.get(&1, :severity) == "error" or Map.get(&1, "severity") == "error"))
      |> Enum.filter(fn d ->
        (Map.get(d, :source) || Map.get(d, "source")) == "elm_ex/typesys"
      end)

    assert errors == [], inspect(errors)
    refute Enum.any?(project.modules, &(&1.name == "Companion.Types"))
  end

  test "accepts Json.Encode.Value on a port and rejects Time.Posix" do
    value_port = port_project("out", "Json.Encode.Value -> Cmd msg")
    {_project, diags} = Check.run(value_port)
    refute Enum.any?(diags, &(&1.code == "port_problem"))

    posix_port = port_project("out", "Time.Posix -> Cmd msg")
    {_project, diags} = Check.run(posix_port)
    assert Enum.any?(diags, &(&1.code == "port_problem"))
  end

  defp load_template_errors(name) do
    template = Path.expand("../../../ide/priv/project_templates/#{name}", __DIR__)

    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-ex-typesys-#{name}-#{System.unique_integer([:positive])}"
      )

    src = Path.join(dir, "src")
    File.mkdir_p!(src)

    Path.wildcard(Path.join(template, "src/**/*.elm"))
    |> Enum.each(fn file ->
      rel = Path.relative_to(file, Path.join(template, "src"))
      dest = Path.join(src, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(file, dest)
    end)

    maybe_copy_protocol(template, dir)
    maybe_copy_resource_manifests(template, dir)

    File.write!(Path.join(dir, "elm.json"), """
    {
      "type": "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": { "elm/core": "1.0.5", "elm/json": "1.1.3" },
        "indirect": {}
      },
      "test-dependencies": { "direct": {}, "indirect": {} }
    }
    """)

    try do
      case Bridge.load_project(dir, lowerer_diagnostics: false) do
        {:ok, project} ->
          (project.diagnostics || [])
          |> Enum.filter(&(Map.get(&1, :severity) == "error" or Map.get(&1, "severity") == "error"))
          |> Enum.filter(fn d ->
            (Map.get(d, :source) || Map.get(d, "source")) == "elm_ex/typesys"
          end)

        {:error, reason} ->
          [%{code: "load_error", message: inspect(reason)}]
      end
    after
      File.rm_rf(dir)
    end
  end

  defp load_source_errors(source) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-ex-typesys-src-#{System.unique_integer([:positive])}"
      )

    src = Path.join(dir, "src")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "Main.elm"), source)

    File.write!(Path.join(dir, "elm.json"), """
    {
      "type": "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": { "elm/core": "1.0.5", "elm/json": "1.1.3" },
        "indirect": {}
      },
      "test-dependencies": { "direct": {}, "indirect": {} }
    }
    """)

    try do
      case Bridge.load_project(dir, lowerer_diagnostics: false) do
        {:ok, project} ->
          (project.diagnostics || [])
          |> Enum.filter(&(Map.get(&1, :severity) == "error" or Map.get(&1, "severity") == "error"))
          |> Enum.filter(fn d ->
            (Map.get(d, :source) || Map.get(d, "source")) == "elm_ex/typesys"
          end)

        {:error, reason} ->
          [%{code: "load_error", message: inspect(reason)}]
      end
    after
      File.rm_rf(dir)
    end
  end

  defp maybe_copy_protocol(template, dir) do
    proto = Path.join(template, "protocol")

    if File.dir?(proto) do
      File.cp_r!(proto, Path.join(dir, "protocol"))
    end
  end

  defp maybe_copy_resource_manifests(template, dir) do
    src = Path.join(template, "resources")

    if File.dir?(src) do
      File.cp_r!(src, Path.join(dir, "resources"))
    end
  end

  defp port_project(name, type) do
    %Project{
      project_dir: "/tmp/typesys-pebble",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [
        %Module{
          name: "Main",
          path: "/tmp/typesys-pebble/src/Main.elm",
          imports: [],
          import_entries: [],
          port_module: true,
          ports: [name],
          declarations: [
            %{kind: :function_signature, name: name, type: type}
          ],
          module_exposing: ".."
        }
      ],
      diagnostics: []
    }
  end

  defp project(decls) do
    %Project{
      project_dir: "/tmp/typesys-pebble",
      elm_json: %{"source-directories" => ["src"], "type" => "application"},
      modules: [
        %Module{
          name: "Main",
          path: "/tmp/typesys-pebble/src/Main.elm",
          imports: [],
          import_entries: [],
          declarations: List.flatten(decls),
          module_exposing: ".."
        }
      ],
      diagnostics: []
    }
  end

  defp function(_mod, name, type, args, expr) do
    [
      %{kind: :function_signature, name: name, type: type, span: %{start_line: 1, end_line: 1}},
      %{
        kind: :function_definition,
        name: name,
        args: args,
        type: type,
        span: %{start_line: 2, end_line: 2},
        expr: expr
      }
    ]
  end
end
