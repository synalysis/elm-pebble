defmodule ElmEx.Typesys.Kernel.Pebble do
  @moduledoc """
  Declared Pebble watch-package schemes (Cmd, Events, Platform, Ui, …).

  Signatures come from `packages/elm-pebble/elm-watch/src/Pebble/*.elm`, not
  C runtime names. Constructors are stored under fully qualified keys so short
  names like `Black` do not collide across modules.
  """

  alias ElmEx.Typesys.{Env, Parser, Type}

  @program_config "{ init : Pebble.Platform.LaunchContext -> (model, Cmd msg), update : msg -> model -> (model, Cmd msg), view : model -> view, subscriptions : model -> Sub msg } -> Program Value model msg"

  @signatures %{
    "Pebble.Cmd.none" => "Cmd msg",
    "Pebble.Cmd.timerAfter" => "Int -> Cmd msg",
    "Pebble.Cmd.getCurrentDateTime" =>
      "(Pebble.Cmd.CurrentDateTime -> msg) -> Cmd msg",
    "Pebble.Cmd.getCurrentTimeString" => "(String -> msg) -> Cmd msg",
    "Pebble.Events.onSecondChange" => "(Int -> msg) -> Sub msg",
    "Pebble.Events.onMinuteChange" => "(Int -> msg) -> Sub msg",
    "Pebble.Events.onHourChange" => "(Int -> msg) -> Sub msg",
    "Pebble.Events.onDayChange" => "(Int -> msg) -> Sub msg",
    "Pebble.Events.onMonthChange" => "(Int -> msg) -> Sub msg",
    "Pebble.Events.onYearChange" => "(Int -> msg) -> Sub msg",
    "Pebble.Events.onAnimationFinished" => "(Pebble.Ui.AnimationId -> msg) -> Sub msg",
    "Pebble.Events.batch" => "List (Sub msg) -> Sub msg",
    "Pebble.Platform.launchReasonToInt" => "Pebble.Platform.LaunchReason -> Int",
    "Pebble.Platform.launchReasonFromTag" => "Int -> Pebble.Platform.LaunchReason",
    "Pebble.Platform.displayShapeIsRound" => "Pebble.Platform.DisplayShape -> Bool",
    "Pebble.Platform.colorCapabilityIsColor" => "Pebble.Platform.ColorCapability -> Bool",
    "Pebble.Platform.onScreenChange" => "(Pebble.Platform.LaunchScreen -> msg) -> Sub msg",
    "Pebble.Platform.watchface" => @program_config,
    "Pebble.Platform.application" => @program_config,
    "Pebble.Platform.worker" => @program_config,
    "Pebble.Time.currentDateTime" => "(Pebble.Time.CurrentDateTime -> msg) -> Cmd msg",
    "Pebble.Time.currentTimeString" => "(String -> msg) -> Cmd msg",
    "Pebble.Time.clockStyle24h" => "(Bool -> msg) -> Cmd msg",
    "Pebble.Time.timezoneIsSet" => "(Bool -> msg) -> Cmd msg",
    "Pebble.Time.timezone" => "(String -> msg) -> Cmd msg",
    "Pebble.Storage.writeInt" => "Int -> Int -> Cmd msg",
    "Pebble.Storage.readInt" => "Int -> (Int -> msg) -> Cmd msg",
    "Pebble.Storage.writeString" => "Int -> String -> Cmd msg",
    "Pebble.Storage.readString" => "Int -> (String -> msg) -> Cmd msg",
    "Pebble.Storage.delete" => "Int -> Cmd msg",
    "Pebble.Storage.maxSize" => "(Int -> msg) -> Cmd msg",
    "Pebble.Button.on" => "Pebble.Button.Button -> Pebble.Button.Event -> msg -> Sub msg",
    "Pebble.Button.onPress" => "Pebble.Button.Button -> msg -> Sub msg",
    "Pebble.Button.onRelease" => "Pebble.Button.Button -> msg -> Sub msg",
    "Pebble.Button.onLongPress" => "Pebble.Button.Button -> msg -> Sub msg",
    "Pebble.WatchInfo.getModel" => "(Pebble.WatchInfo.WatchModel -> msg) -> Cmd msg",
    "Pebble.WatchInfo.getFirmwareVersion" =>
      "(Pebble.WatchInfo.FirmwareVersion -> msg) -> Cmd msg",
    "Pebble.WatchInfo.getColor" => "(Pebble.WatchInfo.WatchColor -> msg) -> Cmd msg",
    "Pebble.WatchInfo.caseColor" => "Pebble.WatchInfo.WatchColor -> Pebble.Ui.Color.Color",
    "Pebble.System.batteryLevel" => "(Int -> msg) -> Cmd msg",
    "Pebble.System.connectionStatus" => "(Bool -> msg) -> Cmd msg",
    "Pebble.System.onBatteryChange" => "(Int -> msg) -> Sub msg",
    "Pebble.System.onConnectionChange" => "(Bool -> msg) -> Sub msg",
    "Pebble.Light.interaction" => "Cmd msg",
    "Pebble.Light.disable" => "Cmd msg",
    "Pebble.Light.enable" => "Cmd msg",
    "Pebble.Light.onChange" => "(Pebble.Light.State -> msg) -> Sub msg",
    "Pebble.Vibes.cancel" => "Cmd msg",
    "Pebble.Vibes.shortPulse" => "Cmd msg",
    "Pebble.Vibes.longPulse" => "Cmd msg",
    "Pebble.Vibes.doublePulse" => "Cmd msg",
    "Pebble.Vibes.pattern" => "List Int -> Cmd msg",
    "Pebble.Alarm.next" => "(Int -> msg) -> Cmd msg",
    "Pebble.Alarm.toPosix" => "Int -> Maybe Posix",
    "Pebble.Wakeup.scheduleAfterSeconds" => "Int -> Cmd msg",
    "Pebble.Wakeup.cancel" => "Int -> Cmd msg",
    "Pebble.Log.infoCode" => "Int -> Cmd msg",
    "Pebble.Log.warnCode" => "Int -> Cmd msg",
    "Pebble.Log.errorCode" => "Int -> Cmd msg",
    "Pebble.AppFocus.onChange" => "(Pebble.AppFocus.State -> msg) -> Sub msg",
    "Pebble.Frame.every" => "Int -> (Pebble.Frame.Frame -> msg) -> Sub msg",
    "Pebble.Frame.atFps" => "Int -> (Pebble.Frame.Frame -> msg) -> Sub msg",
    "Pebble.Ui.windowStack" => "List Pebble.Ui.WindowNode -> Pebble.Ui.UiNode",
    "Pebble.Ui.window" => "Int -> List Pebble.Ui.LayerNode -> Pebble.Ui.WindowNode",
    "Pebble.Ui.canvasLayer" => "Int -> List Pebble.Ui.RenderOp -> Pebble.Ui.LayerNode",
    "Pebble.Ui.toUiNode" => "List Pebble.Ui.RenderOp -> Pebble.Ui.UiNode",
    "Pebble.Ui.textInt" => "Pebble.Ui.Font -> Pebble.Ui.Point -> Int -> Pebble.Ui.RenderOp",
    "Pebble.Ui.textLabel" =>
      "Pebble.Ui.Font -> Pebble.Ui.Point -> Pebble.Ui.Label -> Pebble.Ui.RenderOp",
    "Pebble.Ui.text" =>
      "Pebble.Ui.Font -> Pebble.Ui.TextOptions -> Pebble.Ui.Rect -> String -> Pebble.Ui.RenderOp",
    "Pebble.Ui.defaultTextOptions" => "Pebble.Ui.TextOptions",
    "Pebble.Ui.alignLeft" => "Pebble.Ui.TextOptions -> Pebble.Ui.TextOptions",
    "Pebble.Ui.alignCenter" => "Pebble.Ui.TextOptions -> Pebble.Ui.TextOptions",
    "Pebble.Ui.alignRight" => "Pebble.Ui.TextOptions -> Pebble.Ui.TextOptions",
    "Pebble.Ui.wordWrap" => "Pebble.Ui.TextOptions -> Pebble.Ui.TextOptions",
    "Pebble.Ui.trailingEllipsis" => "Pebble.Ui.TextOptions -> Pebble.Ui.TextOptions",
    "Pebble.Ui.fillOverflow" => "Pebble.Ui.TextOptions -> Pebble.Ui.TextOptions",
    "Pebble.Ui.clear" => "Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.fillRect" => "Pebble.Ui.Rect -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.pixel" => "Pebble.Ui.Point -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.line" =>
      "Pebble.Ui.Point -> Pebble.Ui.Point -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.rect" => "Pebble.Ui.Rect -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.circle" => "Pebble.Ui.Point -> Int -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.fillCircle" => "Pebble.Ui.Point -> Int -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.context" =>
      "List Pebble.Ui.ContextSetting -> List Pebble.Ui.RenderOp -> Pebble.Ui.Context",
    "Pebble.Ui.drawBitmapInRect" =>
      "Pebble.Ui.StaticBitmap -> Pebble.Ui.Rect -> Pebble.Ui.RenderOp",
    "Pebble.Ui.drawBitmapSequenceAt" =>
      "Pebble.Ui.AnimationId -> Pebble.Ui.AnimatedBitmap -> Pebble.Ui.Point -> Pebble.Ui.RenderOp",
    "Pebble.Ui.drawRotatedBitmap" =>
      "Pebble.Ui.StaticBitmap -> Pebble.Ui.Rect -> Pebble.Ui.Rotation -> Pebble.Ui.Point -> Pebble.Ui.RenderOp",
    "Pebble.Ui.drawVectorAt" => "Pebble.Ui.StaticVector -> Pebble.Ui.Point -> Pebble.Ui.RenderOp",
    "Pebble.Ui.drawVectorSequenceAt" =>
      "Pebble.Ui.AnimationId -> Pebble.Ui.AnimatedVector -> Pebble.Ui.Point -> Pebble.Ui.RenderOp",
    "Pebble.Ui.group" => "Pebble.Ui.Context -> Pebble.Ui.RenderOp",
    "Pebble.Ui.path" => "List Pebble.Ui.Point -> Pebble.Ui.Point -> Pebble.Ui.Rotation -> Pebble.Ui.Path",
    "Pebble.Ui.rotationFromPebbleAngle" => "Int -> Pebble.Ui.Rotation",
    "Pebble.Ui.rotationFromDegrees" => "Float -> Pebble.Ui.Rotation",
    "Pebble.Ui.pathFilled" => "Pebble.Ui.Path -> Pebble.Ui.RenderOp",
    "Pebble.Ui.pathOutline" => "Pebble.Ui.Path -> Pebble.Ui.RenderOp",
    "Pebble.Ui.pathOutlineOpen" => "Pebble.Ui.Path -> Pebble.Ui.RenderOp",
    "Pebble.Ui.strokeWidth" => "Int -> Pebble.Ui.ContextSetting",
    "Pebble.Ui.antialiased" => "Int -> Pebble.Ui.ContextSetting",
    "Pebble.Ui.strokeColor" => "Pebble.Ui.Color.Color -> Pebble.Ui.ContextSetting",
    "Pebble.Ui.fillColor" => "Pebble.Ui.Color.Color -> Pebble.Ui.ContextSetting",
    "Pebble.Ui.textColor" => "Pebble.Ui.Color.Color -> Pebble.Ui.ContextSetting",
    "Pebble.Ui.roundRect" => "Pebble.Ui.Rect -> Int -> Pebble.Ui.Color.Color -> Pebble.Ui.RenderOp",
    "Pebble.Ui.arc" => "Pebble.Ui.Rect -> Int -> Int -> Pebble.Ui.RenderOp",
    "Pebble.Ui.fillRadial" => "Pebble.Ui.Rect -> Int -> Int -> Pebble.Ui.RenderOp",
    "Pebble.Ui.compositingMode" => "Int -> Pebble.Ui.ContextSetting",
    "Pebble.Ui.Color.argb8" => "Int -> Pebble.Ui.Color.Color",
    "Pebble.Ui.Color.indexed" => "Int -> Pebble.Ui.Color.Color",
    "Pebble.Ui.Color.rgb" => "Int -> Int -> Int -> Pebble.Ui.Color.Color",
    "Pebble.Ui.Color.rgba" => "Int -> Int -> Int -> Int -> Pebble.Ui.Color.Color",
    "Pebble.Ui.Color.toInt" => "Pebble.Ui.Color.Color -> Int"
  }

  @color_values ~w(
    clearColor black oxfordBlue dukeBlue blue darkGreen midnightGreen cobaltBlue
    blueMoon islamicGreen jaegerGreen tiffanyBlue vividCerulean green malachite
    mediumSpringGreen cyan bulgarianRose imperialPurple indigo electricUltramarine
    armyGreen darkGray liberty veryLightBlue kellyGreen mayGreen cadetBlue pictonBlue
    brightGreen screaminGreen mediumAquamarine electricBlue darkCandyAppleRed
    jazzberryJam purple vividViolet windsorTan roseVale purpureus lavenderIndigo
    limerick brass lightGray babyBlueEyes springBud inchworm mintGreen celeste red
    folly fashionMagenta magenta orange sunsetOrange brilliantRose shockingPink
    chromeYellow rajah melon richBrilliantLavender yellow icterine pastelYellow white
  )

  @constructors [
    {"Pebble.Platform.LaunchSystem", "Pebble.Platform.LaunchReason", 0, "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchUser", "Pebble.Platform.LaunchReason", 0, "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchPhone", "Pebble.Platform.LaunchReason", 0, "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchWakeup", "Pebble.Platform.LaunchReason", 0, "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchWorker", "Pebble.Platform.LaunchReason", 0, "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchQuickLaunch", "Pebble.Platform.LaunchReason", 0,
     "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchTimelineAction", "Pebble.Platform.LaunchReason", 0,
     "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchSmartstrap", "Pebble.Platform.LaunchReason", 0,
     "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.LaunchUnknown", "Pebble.Platform.LaunchReason", 0, "Pebble.Platform.LaunchReason"},
    {"Pebble.Platform.QuickLaunchNone", "Pebble.Platform.QuickLaunchAction", 0,
     "Pebble.Platform.QuickLaunchAction"},
    {"Pebble.Platform.QuickLaunchHold", "Pebble.Platform.QuickLaunchAction", 0,
     "Pebble.Platform.QuickLaunchAction"},
    {"Pebble.Platform.QuickLaunchTap", "Pebble.Platform.QuickLaunchAction", 0,
     "Pebble.Platform.QuickLaunchAction"},
    {"Pebble.Platform.QuickLaunchCombo", "Pebble.Platform.QuickLaunchAction", 0,
     "Pebble.Platform.QuickLaunchAction"},
    {"Pebble.Platform.QuickLaunchUnknown", "Pebble.Platform.QuickLaunchAction", 0,
     "Pebble.Platform.QuickLaunchAction"},
    {"Pebble.Platform.Rectangular", "Pebble.Platform.DisplayShape", 0, "Pebble.Platform.DisplayShape"},
    {"Pebble.Platform.Round", "Pebble.Platform.DisplayShape", 0, "Pebble.Platform.DisplayShape"},
    {"Pebble.Platform.BlackWhite", "Pebble.Platform.ColorCapability", 0,
     "Pebble.Platform.ColorCapability"},
    {"Pebble.Platform.Color", "Pebble.Platform.ColorCapability", 0, "Pebble.Platform.ColorCapability"},
    {"Pebble.Button.Back", "Pebble.Button.Button", 0, "Pebble.Button.Button"},
    {"Pebble.Button.Up", "Pebble.Button.Button", 0, "Pebble.Button.Button"},
    {"Pebble.Button.Select", "Pebble.Button.Button", 0, "Pebble.Button.Button"},
    {"Pebble.Button.Down", "Pebble.Button.Button", 0, "Pebble.Button.Button"},
    {"Pebble.Button.Pressed", "Pebble.Button.Event", 0, "Pebble.Button.Event"},
    {"Pebble.Button.Released", "Pebble.Button.Event", 0, "Pebble.Button.Event"},
    {"Pebble.Button.LongPressed", "Pebble.Button.Event", 0, "Pebble.Button.Event"},
    {"Pebble.Time.Monday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Time.Tuesday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Time.Wednesday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Time.Thursday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Time.Friday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Time.Saturday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Time.Sunday", "Pebble.Time.DayOfWeek", 0, "Pebble.Time.DayOfWeek"},
    {"Pebble.Light.On", "Pebble.Light.State", 0, "Pebble.Light.State"},
    {"Pebble.Light.Off", "Pebble.Light.State", 0, "Pebble.Light.State"},
    {"Pebble.AppFocus.InFocus", "Pebble.AppFocus.State", 0, "Pebble.AppFocus.State"},
    {"Pebble.AppFocus.OutOfFocus", "Pebble.AppFocus.State", 0, "Pebble.AppFocus.State"},
    {"Pebble.Ui.AnimationId", "Pebble.Ui.AnimationId", 1, "Int -> Pebble.Ui.AnimationId"},
    {"Pebble.Ui.WaitingForCompanion", "Pebble.Ui.Label", 0, "Pebble.Ui.Label"},
    {"Pebble.Ui.AlignLeft", "Pebble.Ui.TextAlignment", 0, "Pebble.Ui.TextAlignment"},
    {"Pebble.Ui.AlignCenter", "Pebble.Ui.TextAlignment", 0, "Pebble.Ui.TextAlignment"},
    {"Pebble.Ui.AlignRight", "Pebble.Ui.TextAlignment", 0, "Pebble.Ui.TextAlignment"},
    {"Pebble.Ui.WordWrap", "Pebble.Ui.TextOverflow", 0, "Pebble.Ui.TextOverflow"},
    {"Pebble.Ui.TrailingEllipsis", "Pebble.Ui.TextOverflow", 0, "Pebble.Ui.TextOverflow"},
    {"Pebble.Ui.Fill", "Pebble.Ui.TextOverflow", 0, "Pebble.Ui.TextOverflow"},
    {"Pebble.Ui.Color.Indexed", "Pebble.Ui.Color.Color", 1, "Int -> Pebble.Ui.Color.Color"},
    {"Pebble.Ui.Color.RGBA", "Pebble.Ui.Color.Color", 4,
     "Int -> Int -> Int -> Int -> Pebble.Ui.Color.Color"}
  ]

  @aliases %{
    "Pebble.Platform.LaunchScreen" =>
      "{ width : Int, height : Int, shape : Pebble.Platform.DisplayShape, colorMode : Pebble.Platform.ColorCapability }",
    "Pebble.Platform.LaunchContext" =>
      "{ reason : Pebble.Platform.LaunchReason, watchModel : String, watchProfileId : String, screen : Pebble.Platform.LaunchScreen, hasMicrophone : Bool, hasCompass : Bool, supportsHealth : Bool, launchButton : Maybe Pebble.Button.Button, quickLaunchAction : Pebble.Platform.QuickLaunchAction }",
    "Pebble.Cmd.Cmd" => "Platform.Cmd",
    "Pebble.Cmd.CurrentDateTime" =>
      "{ year : Int, month : Int, day : Int, dayOfWeek : Weekday, hour : Int, minute : Int, second : Int, utcOffsetMinutes : Int }",
    "Pebble.Time.CurrentDateTime" =>
      "{ year : Int, month : Int, day : Int, dayOfWeek : Pebble.Time.DayOfWeek, hour : Int, minute : Int, second : Int, utcOffsetMinutes : Int }",
    "Pebble.WatchInfo.FirmwareVersion" => "{ major : Int, minor : Int, patch : Int }",
    "Pebble.Frame.Frame" => "{ dtMs : Int, elapsedMs : Int, frame : Int }",
    "Pebble.Ui.Point" => "{ x : Int, y : Int }",
    "Pebble.Ui.Rect" => "{ x : Int, y : Int, w : Int, h : Int }",
    "Pebble.Ui.TextOptions" =>
      "{ alignment : Pebble.Ui.TextAlignment, overflow : Pebble.Ui.TextOverflow }",
    "Pebble.Ui.Font" => "Pebble.Ui.Resources.Font",
    "Pebble.Ui.StaticBitmap" => "Pebble.Ui.Resources.StaticBitmap",
    "Pebble.Ui.AnimatedBitmap" => "Pebble.Ui.Resources.AnimatedBitmap",
    "Pebble.Ui.StaticVector" => "Pebble.Ui.Resources.StaticVector",
    "Pebble.Ui.AnimatedVector" => "Pebble.Ui.Resources.AnimatedVector",
    "Pebble.Ui.Context" => "(List Pebble.Ui.ContextSetting, List Pebble.Ui.RenderOp)",
    "Pebble.Ui.Path" => "(List (Int, Int), (Int, Int), Int)"
  }

  @spec install(Env.t()) :: Env.t()
  def install(env) do
    env
    |> install_aliases()
    |> install_signatures()
    |> install_call_shorthands()
    |> install_color_values()
    |> install_constructors()
    |> ElmEx.Typesys.Kernel.PebbleDevices.install()
    |> ElmEx.Typesys.Kernel.PebbleCompanion.install()
  end

  defp install_signatures(env) do
    Enum.reduce(@signatures, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} -> Env.put_value(acc, name, Env.generalize(acc, type))
        {:error, _} -> acc
      end
    end)
  end

  # Compiler-accepted call shapes that are not the primary package signature.
  @call_shorthands [
    {"Pebble.Ui.text", "String -> Pebble.Ui.RenderOp"},
    {"Pebble.Ui.textLabel", "Pebble.Ui.Font -> Pebble.Ui.Point -> String -> Pebble.Ui.RenderOp"},
    {"Pebble.Ui.toUiNode", "Pebble.Ui.RenderOp -> Pebble.Ui.UiNode"},
    {"Pebble.Ui.group", "List Pebble.Ui.RenderOp -> Pebble.Ui.RenderOp"}
  ]

  defp install_call_shorthands(env) do
    Enum.reduce(@call_shorthands, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} -> Env.put_alt(acc, name, Env.generalize(acc, type))
        {:error, _} -> acc
      end
    end)
  end

  defp install_color_values(env) do
    color = Type.named("Pebble.Ui.Color.Color")
    scheme = Env.generalize(env, color)

    Enum.reduce(@color_values, env, fn name, acc ->
      Env.put_value(acc, "Pebble.Ui.Color.#{name}", scheme)
    end)
  end

  defp install_constructors(env) do
    Enum.reduce(@constructors, env, fn {name, union, arity, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} ->
          scheme = Env.generalize(acc, type)

          info = %{
            name: name,
            union: union,
            arity: arity,
            scheme: scheme
          }

          acc
          |> Map.update!(:constructors, &Map.put(&1, name, info))
          |> Env.put_value(name, scheme)

        {:error, _} ->
          acc
      end
    end)
  end

  defp install_aliases(env) do
    Enum.reduce(@aliases, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, body} ->
          fields =
            case body do
              {:record, fs, _} -> fs
              _ -> %{}
            end

          Env.put_alias(acc, name, %{
            name: name,
            params: [],
            body: body,
            fields: fields
          })

        {:error, _} ->
          acc
      end
    end)
  end
end
