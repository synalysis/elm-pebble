defmodule ElmEx.Typesys.Kernel.PebbleDevices do
  @moduledoc """
  Remaining watch-package schemes: Health, Touch, Speaker, Compass, Accel,
  UnobstructedArea, DataLog, Dictation, WatchInfo constructors, Resources,
  and Pebble.Game helpers.
  """

  alias ElmEx.Typesys.{Env, Parser}

  @signatures %{
    "Pebble.Health.supported" => "(Bool -> msg) -> Cmd msg",
    "Pebble.Health.value" => "Pebble.Health.Metric -> (Int -> msg) -> Cmd msg",
    "Pebble.Health.sumToday" => "Pebble.Health.Metric -> (Int -> msg) -> Cmd msg",
    "Pebble.Health.sum" => "Pebble.Health.Metric -> Int -> Int -> (Int -> msg) -> Cmd msg",
    "Pebble.Health.accessible" => "Pebble.Health.Metric -> Int -> Int -> (Bool -> msg) -> Cmd msg",
    "Pebble.Health.hrvPpiMs" => "(Int -> msg) -> Cmd msg",
    "Pebble.Health.setHeartRateSamplePeriod" => "Int -> Cmd msg",
    "Pebble.Health.setHrvSamplePeriod" => "Int -> Cmd msg",
    "Pebble.Health.onEvent" => "(Pebble.Health.Event -> msg) -> Sub msg",
    "Pebble.Touch.supported" => "(Bool -> msg) -> Cmd msg",
    "Pebble.Touch.enableNavigation" => "Cmd msg",
    "Pebble.Touch.onTap" => "(Pebble.Touch.Point -> msg) -> Sub msg",
    "Pebble.Touch.onPan" => "Pebble.Touch.Axis -> (Pebble.Touch.PanEvent -> msg) -> Sub msg",
    "Pebble.Touch.onSwipe" =>
      "List Pebble.Touch.Direction -> (Pebble.Touch.SwipeEvent -> msg) -> Sub msg",
    "Pebble.Compass.current" =>
      "(Result Pebble.Compass.Error Pebble.Compass.Heading -> msg) -> Cmd msg",
    "Pebble.Compass.onChange" => "(Pebble.Compass.Heading -> msg) -> Sub msg",
    "Pebble.Accel.defaultConfig" => "Pebble.Accel.Config",
    "Pebble.Accel.onData" => "Pebble.Accel.Config -> (Pebble.Accel.Sample -> msg) -> Sub msg",
    "Pebble.Accel.onTap" => "msg -> Sub msg",
    "Pebble.UnobstructedArea.onWillChange" => "(Pebble.Ui.Rect -> msg) -> Sub msg",
    "Pebble.UnobstructedArea.onChanging" => "(Int -> msg) -> Sub msg",
    "Pebble.UnobstructedArea.onDidChange" => "msg -> Sub msg",
    "Pebble.UnobstructedArea.currentBounds" => "(Pebble.Ui.Rect -> msg) -> Cmd msg",
    "Pebble.DataLog.tag" => "Int -> Pebble.DataLog.Tag",
    "Pebble.DataLog.logBytes" => "Pebble.DataLog.Tag -> List Int -> Cmd msg",
    "Pebble.DataLog.logInt32" => "Pebble.DataLog.Tag -> Int -> Cmd msg",
    "Pebble.Dictation.start" => "Cmd msg",
    "Pebble.Dictation.stop" => "Cmd msg",
    "Pebble.Dictation.onStatus" => "(Pebble.Dictation.Status -> msg) -> Sub msg",
    "Pebble.Dictation.onResult" =>
      "(Result Pebble.Dictation.Error String -> msg) -> Sub msg",
    "Pebble.Speaker.maxNotes" => "Int",
    "Pebble.Speaker.maxTracks" => "Int",
    "Pebble.Speaker.maxSampleBytesTotal" => "Int",
    "Pebble.Speaker.limits" => "Pebble.Speaker.Limits",
    "Pebble.Speaker.playTone" => "Int -> Int -> Int -> Pebble.Speaker.Waveform -> Cmd msg",
    "Pebble.Speaker.playNotes" => "List Pebble.Speaker.Note -> Int -> Cmd msg",
    "Pebble.Speaker.playTracks" => "List Pebble.Speaker.Track -> Int -> Cmd msg",
    "Pebble.Speaker.stop" => "Cmd msg",
    "Pebble.Speaker.setVolume" => "Int -> Cmd msg",
    "Pebble.Speaker.status" => "(Pebble.Speaker.Status -> msg) -> Cmd msg",
    "Pebble.Speaker.isMuted" => "(Bool -> msg) -> Cmd msg",
    "Pebble.Speaker.streamOpen" => "Pebble.Speaker.PcmFormat -> Int -> Cmd msg",
    "Pebble.Speaker.streamWrite" => "List Int -> Cmd msg",
    "Pebble.Speaker.streamClose" => "Cmd msg",
    "Pebble.Speaker.onFinished" => "(Pebble.Speaker.FinishReason -> msg) -> Sub msg",
    "Pebble.Speaker.Resources.sampleId" => "Pebble.Speaker.Resources.Sample -> Int",
    "Pebble.Speaker.Resources.allSamples" => "List Pebble.Speaker.Resources.Sample",
    "Pebble.Internal.Companion.companionSend" => "Int -> Int -> Cmd msg",
    "Pebble.Ui.Resources.allStaticBitmaps" => "List Pebble.Ui.Resources.StaticBitmap",
    "Pebble.Ui.Resources.allAnimatedBitmaps" => "List Pebble.Ui.Resources.AnimatedBitmap",
    "Pebble.Ui.Resources.allFonts" => "List Pebble.Ui.Resources.Font",
    "Pebble.Ui.Resources.allStaticVectors" => "List Pebble.Ui.Resources.StaticVector",
    "Pebble.Ui.Resources.allAnimatedVectors" => "List Pebble.Ui.Resources.AnimatedVector",
    "Pebble.Ui.Resources.staticBitmapInfo" =>
      "Pebble.Ui.Resources.StaticBitmap -> Pebble.Ui.Resources.StaticBitmapInfo",
    "Pebble.Ui.Resources.animatedBitmapInfo" =>
      "Pebble.Ui.Resources.AnimatedBitmap -> Pebble.Ui.Resources.AnimatedBitmapInfo",
    "Pebble.Ui.Resources.fontInfo" => "Pebble.Ui.Resources.Font -> Pebble.Ui.Resources.FontInfo",
    "Pebble.Ui.Resources.staticVectorInfo" =>
      "Pebble.Ui.Resources.StaticVector -> Pebble.Ui.Resources.StaticVectorInfo",
    "Pebble.Ui.Resources.animatedVectorInfo" =>
      "Pebble.Ui.Resources.AnimatedVector -> Pebble.Ui.Resources.AnimatedVectorInfo",
    "Pebble.Game.Collision.rectRect" =>
      "Pebble.Game.Collision.Rect -> Pebble.Game.Collision.Rect -> Bool",
    "Pebble.Game.Collision.pointInRect" =>
      "{ x : Int, y : Int } -> Pebble.Game.Collision.Rect -> Bool",
    "Pebble.Game.Collision.circleCircle" =>
      "Pebble.Game.Collision.Circle -> Pebble.Game.Collision.Circle -> Bool",
    "Pebble.Game.Math.vec2" => "Float -> Float -> Pebble.Game.Math.Vec2",
    "Pebble.Game.Math.add" => "Pebble.Game.Math.Vec2 -> Pebble.Game.Math.Vec2 -> Pebble.Game.Math.Vec2",
    "Pebble.Game.Math.sub" => "Pebble.Game.Math.Vec2 -> Pebble.Game.Math.Vec2 -> Pebble.Game.Math.Vec2",
    "Pebble.Game.Math.scale" => "Float -> Pebble.Game.Math.Vec2 -> Pebble.Game.Math.Vec2",
    "Pebble.Game.Math.lengthSquared" => "Pebble.Game.Math.Vec2 -> Float",
    "Pebble.Game.Math.distanceSquared" =>
      "Pebble.Game.Math.Vec2 -> Pebble.Game.Math.Vec2 -> Float",
    "Pebble.Game.Math.clamp" => "comparable -> comparable -> comparable -> comparable",
    "Pebble.Game.Sprite.sprite" =>
      "Pebble.Ui.StaticBitmap -> Pebble.Ui.Rect -> Pebble.Game.Sprite.Sprite",
    "Pebble.Game.Sprite.view" => "Pebble.Game.Sprite.Sprite -> Pebble.Ui.RenderOp",
    "Pebble.Game.Sprite.parallaxBitmap" =>
      "Pebble.Ui.StaticBitmap -> { x : Int, y : Int, w : Int, h : Int } -> Int -> List Pebble.Ui.RenderOp",
    "Pebble.Game.Sprite.tileMap" =>
      "{ tileSize : Int, cameraX : Int, cameraY : Int, tiles : List (Int, Int, Pebble.Ui.StaticBitmap) } -> List Pebble.Ui.RenderOp"
  }

  @aliases %{
    "Pebble.Touch.Point" => "{ x : Int, y : Int }",
    "Pebble.Touch.PanEvent" =>
      "{ phase : Pebble.Touch.Phase, totalX : Int, totalY : Int, sinceStartX : Int, sinceStartY : Int, velocityX : Int, velocityY : Int }",
    "Pebble.Touch.SwipeEvent" =>
      "{ direction : Pebble.Touch.Direction, velocityX : Int, velocityY : Int }",
    "Pebble.Compass.Heading" => "{ degrees : Float, isValid : Bool }",
    "Pebble.Accel.Config" =>
      "{ samplesPerUpdate : Int, samplingRate : Pebble.Accel.SamplingRate }",
    "Pebble.Accel.Sample" => "{ x : Int, y : Int, z : Int }",
    "Pebble.Speaker.Note" =>
      "{ midiNote : Int, waveform : Pebble.Speaker.Waveform, durationMs : Int, velocity : Int }",
    "Pebble.Speaker.Track" =>
      "{ notes : List Pebble.Speaker.Note, sample : Maybe Pebble.Speaker.Resources.Sample }",
    "Pebble.Speaker.Limits" =>
      "{ maxNotes : Int, maxTracks : Int, maxSampleBytesTotal : Int }",
    "Pebble.Ui.Resources.StaticBitmapInfo" =>
      "{ staticBitmap : Pebble.Ui.Resources.StaticBitmap, name : String, width : Int, height : Int }",
    "Pebble.Ui.Resources.AnimatedBitmapInfo" =>
      "{ animatedBitmap : Pebble.Ui.Resources.AnimatedBitmap, name : String, width : Int, height : Int, frameCount : Int, durationMs : Int }",
    "Pebble.Ui.Resources.FontInfo" =>
      "{ font : Pebble.Ui.Resources.Font, name : String, height : Int }",
    "Pebble.Ui.Resources.StaticVectorInfo" =>
      "{ staticVector : Pebble.Ui.Resources.StaticVector, name : String }",
    "Pebble.Ui.Resources.AnimatedVectorInfo" =>
      "{ animatedVector : Pebble.Ui.Resources.AnimatedVector, name : String }",
    "Pebble.Game.Collision.Rect" => "{ x : Int, y : Int, w : Int, h : Int }",
    "Pebble.Game.Collision.Circle" => "{ x : Int, y : Int, r : Int }",
    "Pebble.Game.Math.Vec2" => "{ x : Float, y : Float }",
    "Pebble.Game.Sprite.Sprite" =>
      "{ bitmap : Pebble.Ui.StaticBitmap, x : Int, y : Int, w : Int, h : Int }"
  }

  @zero_ctors [
    {"Pebble.Health.StepCount", "Pebble.Health.Metric"},
    {"Pebble.Health.ActiveSeconds", "Pebble.Health.Metric"},
    {"Pebble.Health.WalkedDistanceMeters", "Pebble.Health.Metric"},
    {"Pebble.Health.SleepSeconds", "Pebble.Health.Metric"},
    {"Pebble.Health.RestfulSleepSeconds", "Pebble.Health.Metric"},
    {"Pebble.Health.RestingKCalories", "Pebble.Health.Metric"},
    {"Pebble.Health.ActiveKCalories", "Pebble.Health.Metric"},
    {"Pebble.Health.HeartRateBPM", "Pebble.Health.Metric"},
    {"Pebble.Health.SignificantUpdate", "Pebble.Health.Event"},
    {"Pebble.Health.MovementUpdate", "Pebble.Health.Event"},
    {"Pebble.Health.SleepUpdate", "Pebble.Health.Event"},
    {"Pebble.Health.HeartRateUpdate", "Pebble.Health.Event"},
    {"Pebble.Health.HrvUpdate", "Pebble.Health.Event"},
    {"Pebble.Touch.Started", "Pebble.Touch.Phase"},
    {"Pebble.Touch.Updated", "Pebble.Touch.Phase"},
    {"Pebble.Touch.Completed", "Pebble.Touch.Phase"},
    {"Pebble.Touch.Cancelled", "Pebble.Touch.Phase"},
    {"Pebble.Touch.Horizontal", "Pebble.Touch.Axis"},
    {"Pebble.Touch.Vertical", "Pebble.Touch.Axis"},
    {"Pebble.Touch.Up", "Pebble.Touch.Direction"},
    {"Pebble.Touch.Down", "Pebble.Touch.Direction"},
    {"Pebble.Touch.Left", "Pebble.Touch.Direction"},
    {"Pebble.Touch.Right", "Pebble.Touch.Direction"},
    {"Pebble.Compass.Unavailable", "Pebble.Compass.Error"},
    {"Pebble.Compass.InvalidReading", "Pebble.Compass.Error"},
    {"Pebble.Accel.Hz10", "Pebble.Accel.SamplingRate"},
    {"Pebble.Accel.Hz25", "Pebble.Accel.SamplingRate"},
    {"Pebble.Accel.Hz50", "Pebble.Accel.SamplingRate"},
    {"Pebble.Accel.Hz100", "Pebble.Accel.SamplingRate"},
    {"Pebble.Dictation.NoMicrophone", "Pebble.Dictation.Error"},
    {"Pebble.Dictation.PhoneDisconnected", "Pebble.Dictation.Error"},
    {"Pebble.Dictation.Cancelled", "Pebble.Dictation.Error"},
    {"Pebble.Dictation.Starting", "Pebble.Dictation.Status"},
    {"Pebble.Dictation.Recognizing", "Pebble.Dictation.Status"},
    {"Pebble.Dictation.Finished", "Pebble.Dictation.Status"},
    {"Pebble.Speaker.Sine", "Pebble.Speaker.Waveform"},
    {"Pebble.Speaker.Square", "Pebble.Speaker.Waveform"},
    {"Pebble.Speaker.Triangle", "Pebble.Speaker.Waveform"},
    {"Pebble.Speaker.Sawtooth", "Pebble.Speaker.Waveform"},
    {"Pebble.Speaker.Pcm8kHz8bit", "Pebble.Speaker.PcmFormat"},
    {"Pebble.Speaker.Pcm16kHz8bit", "Pebble.Speaker.PcmFormat"},
    {"Pebble.Speaker.Pcm8kHz16bit", "Pebble.Speaker.PcmFormat"},
    {"Pebble.Speaker.Pcm16kHz16bit", "Pebble.Speaker.PcmFormat"},
    {"Pebble.Speaker.Idle", "Pebble.Speaker.Status"},
    {"Pebble.Speaker.Playing", "Pebble.Speaker.Status"},
    {"Pebble.Speaker.Draining", "Pebble.Speaker.Status"},
    {"Pebble.Speaker.FinishedDone", "Pebble.Speaker.FinishReason"},
    {"Pebble.Speaker.FinishedStopped", "Pebble.Speaker.FinishReason"},
    {"Pebble.Speaker.FinishedPreempted", "Pebble.Speaker.FinishReason"},
    {"Pebble.Speaker.FinishedError", "Pebble.Speaker.FinishReason"},
    {"Pebble.Speaker.FinishedUnknown", "Pebble.Speaker.FinishReason"},
    {"Pebble.Speaker.Resources.NoSample", "Pebble.Speaker.Resources.Sample"},
    {"Pebble.Ui.Resources.NoStaticBitmap", "Pebble.Ui.Resources.StaticBitmap"},
    {"Pebble.Ui.Resources.NoAnimatedBitmap", "Pebble.Ui.Resources.AnimatedBitmap"},
    {"Pebble.Ui.Resources.DefaultFont", "Pebble.Ui.Resources.Font"},
    {"Pebble.Ui.Resources.NoStaticVector", "Pebble.Ui.Resources.StaticVector"},
    {"Pebble.Ui.Resources.NoAnimatedVector", "Pebble.Ui.Resources.AnimatedVector"}
  ]

  @payload_ctors [
    {"Pebble.Dictation.Failed", "Pebble.Dictation.Error", 1, "String -> Pebble.Dictation.Error"},
    {"Pebble.DataLog.Tag", "Pebble.DataLog.Tag", 1, "Int -> Pebble.DataLog.Tag"}
  ]

  @spec install(Env.t()) :: Env.t()
  def install(env) do
    env
    |> install_aliases()
    |> install_signatures()
    |> install_zero_ctors()
    |> install_payload_ctors()
  end

  defp watch_info_ctors do
    models = ~w(
      UnknownModel PebbleOriginal PebbleSteel PebbleTime PebbleTimeSteel
      PebbleTimeRound14 PebbleTimeRound20 Pebble2Hr Pebble2Se PebbleTime2
      CoreDevicesP2D CoreDevicesPT2 CoreDevicesPR2
    )

    colors = ~w(
      UnknownColor Black White Red Orange Gray StainlessSteel MatteBlack Blue
      Green Pink TimeWhite TimeBlack TimeRed TimeSteelSilver TimeSteelBlack
      TimeSteelGold TimeRoundSilver14 TimeRoundBlack14 TimeRoundSilver20
      TimeRoundBlack20 TimeRoundRoseGold14 Pebble2HrBlack Pebble2HrLime
      Pebble2HrFlame Pebble2HrWhite Pebble2HrAqua Pebble2SeBlack Pebble2SeWhite
      PebbleTime2Black PebbleTime2Silver PebbleTime2Gold CoreDevicesP2DBlack
      CoreDevicesP2DWhite CoreDevicesPT2BlackGrey CoreDevicesPT2BlackRed
      CoreDevicesPT2SilverBlue CoreDevicesPT2SilverGrey CoreDevicesPR2Black20
      CoreDevicesPR2Silver20 CoreDevicesPR2Gold14 CoreDevicesPR2Silver14
    )

    Enum.map(models, &{"Pebble.WatchInfo.#{&1}", "Pebble.WatchInfo.WatchModel"}) ++
      Enum.map(colors, &{"Pebble.WatchInfo.#{&1}", "Pebble.WatchInfo.WatchColor"})
  end

  defp install_signatures(env) do
    Enum.reduce(@signatures, env, fn {name, src}, acc ->
      put_parsed(acc, name, src, fn acc, type -> Env.put_value(acc, name, Env.generalize(acc, type)) end)
    end)
  end

  defp install_aliases(env) do
    Enum.reduce(@aliases, env, fn {name, src}, acc ->
      put_parsed(acc, name, src, fn acc, body ->
        fields =
          case body do
            {:record, fs, _} -> fs
            _ -> %{}
          end

        Env.put_alias(acc, name, %{name: name, params: [], body: body, fields: fields})
      end)
    end)
  end

  defp install_zero_ctors(env) do
    Enum.reduce(@zero_ctors ++ watch_info_ctors(), env, fn {name, union}, acc ->
      put_ctor(acc, name, union, 0, union)
    end)
  end

  defp install_payload_ctors(env) do
    Enum.reduce(@payload_ctors, env, fn {name, union, arity, src}, acc ->
      put_ctor(acc, name, union, arity, src)
    end)
  end

  defp put_ctor(env, name, union, arity, src) do
    put_parsed(env, name, src, fn acc, type ->
      scheme = Env.generalize(acc, type)
      info = %{name: name, union: union, arity: arity, scheme: scheme}

      acc
      |> Map.update!(:constructors, &Map.put(&1, name, info))
      |> Env.put_value(name, scheme)
    end)
  end

  defp put_parsed(env, _name, src, fun) do
    case Parser.parse(src) do
      {:ok, type} -> fun.(env, type)
      {:error, _} -> env
    end
  end
end
