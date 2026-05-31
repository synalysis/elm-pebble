defmodule Ide.Debugger.TemplateWatchfaceIntegrationTest do
  @moduledoc false
  use Ide.DebuggerIntegrationCase, async: false

  alias Ide.DebuggerIntegrationExecutors.AccelRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.AliveGuardFrameExecutor
  alias Ide.DebuggerIntegrationExecutors.DebuggerRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.FailingExternalRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.FrameRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.HttpFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.InitNoFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.InitRandomFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.MaybeShapeRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.NilMaybeRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.StorageFollowupRuntimeExecutor
  alias Ide.DebuggerIntegrationExecutors.TupleMaybeRuntimeExecutor

  test "watchface digital source-only runtime does not invent launch model aliases" do
    slug = "sim-watchface-centered-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watchface_digital", "src", "Main.elm"]))

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "center_check",
        source_root: "watch"
      })

    assert {:ok, ticked} = Debugger.tick(slug, %{target: "watch", count: 1})
    runtime_model = get_in(ticked, [:watch, :model, "runtime_model"]) || %{}

    refute Map.has_key?(runtime_model, "width")
    refute Map.has_key?(runtime_model, "height")
    refute Map.has_key?(runtime_model, "screenWidth")
    refute Map.has_key?(runtime_model, "screenHeight")
  end


  test "tutorial watchface source-only init hydrates static constructors without inventing launch fields" do
    slug = "sim-tutorial-init-hydration-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_init_hydration",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
    assert runtime_model["connected"] == %{"ctor" => "Just", "args" => [true]}
    assert runtime_model["showDate"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["backgroundColor"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["textColor"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["condition"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["temperature"] == %{"ctor" => "Nothing", "args" => []}
    assert get_in(runtime_model, ["currentDateTime", "ctor"]) == "Just"
    assert [current_date_time] = get_in(runtime_model, ["currentDateTime", "args"])
    assert current_date_time["year"] >= 2000
    assert current_date_time["utcOffsetMinutes"] == 120
    refute Map.has_key?(runtime_model, "width")
    refute Map.has_key?(runtime_model, "height")
    refute Map.has_key?(runtime_model, "screenWidth")
    refute Map.has_key?(runtime_model, "screenHeight")
    refute Map.has_key?(runtime_model, "hour")
    refute Map.has_key?(runtime_model, "dayOfWeek")
  end


  test "tangram watchface runtime model stays free of weather and message ctor pollution" do
    slug = "sim-tangram-model-purity-#{System.unique_integer([:positive])}"

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "src", "Main.elm"])
      )

    companion_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "phone", "src", "CompanionApp.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, watch_reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: watch_source,
               reason: "tangram_watch_model_purity",
               source_root: "watch"
             })

    watch_runtime_model = get_in(watch_reloaded, [:watch, :model, "runtime_model"]) || %{}

    refute Map.has_key?(watch_runtime_model, "condition")
    refute Map.has_key?(watch_runtime_model, "temperature")
    refute Map.has_key?(watch_runtime_model, "displayedCondition")
    refute Map.has_key?(watch_runtime_model, "displayedTemperature")
    assert Map.has_key?(watch_runtime_model, "companionFigure")

    assert {:ok, companion_reloaded} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: companion_source,
               reason: "tangram_companion_model_purity",
               source_root: "phone"
             })

    companion_runtime_model = get_in(companion_reloaded, [:companion, :model, "runtime_model"]) || %{}

    assert Map.get(companion_runtime_model, "figure") in [0, nil]

    if Map.has_key?(companion_runtime_model, "names") do
      assert is_list(companion_runtime_model["names"]) or is_binary(companion_runtime_model["names"])
    end
    refute Map.has_key?(companion_runtime_model, "ctor")
    refute Map.has_key?(companion_runtime_model, "args")
    refute Map.has_key?(companion_runtime_model, "$ctor")
    refute Map.has_key?(companion_runtime_model, "$args")
  end


  test "tangram debugger bootstrap order yields a single watch init" do
    slug = "sim-tangram-bootstrap-order-#{System.unique_integer([:positive])}"

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "src", "Main.elm"])
      )

    companion_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "phone", "src", "CompanionApp.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               reason: "tangram_watch_bootstrap",
               source_root: "watch"
             })

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: companion_source,
               reason: "tangram_companion_bootstrap",
               source_root: "phone"
             })

    watch_inits =
      reloaded.debugger_timeline
      |> Enum.filter(&(&1.type == "init" and &1.target == "watch"))
      |> Enum.map(& &1.seq)

    current_date_time_updates =
      reloaded.debugger_timeline
      |> Enum.filter(&(&1.type == "update" and &1.target == "watch"))
      |> Enum.filter(&(String.contains?(&1.message, "CurrentDateTime")))
      |> Enum.map(& &1.seq)

    assert watch_inits == [1]
    assert current_date_time_updates == [2]

    phone_inits =
      reloaded.debugger_timeline
      |> Enum.filter(&(&1.type == "init" and &1.target == "phone"))
      |> Enum.map(& &1.seq)

    assert phone_inits == [3]
    refute AppMessageQueue.pending?(reloaded, :companion)
    refute AppMessageQueue.pending?(reloaded, :watch)
  end


  test "tangram companion init schedules catalog http follow-up on debugger timeline" do
    previous_async_http = Application.get_env(:ide, :debugger_async_http_followups)

    Application.put_env(:ide, :debugger_async_http_followups, true)

    on_exit(fn ->
      if is_nil(previous_async_http) do
        Application.delete_env(:ide, :debugger_async_http_followups)
      else
        Application.put_env(:ide, :debugger_async_http_followups, previous_async_http)
      end
    end)

    slug = "sim-tangram-catalog-http-timeline-#{System.unique_integer([:positive])}"

    companion_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "phone", "src", "CompanionApp.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: companion_source,
               reason: "tangram_catalog_http_timeline",
               source_root: "phone"
             })

    pending_http =
      reloaded.debugger_timeline
      |> Enum.filter(&(Map.get(&1, :message_source) == "http_pending"))

    assert pending_http != [],
           "expected http_pending timeline row when catalog GET is enqueued, got: #{inspect(reloaded.debugger_timeline)}"

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)

    assert {:ok, reloaded} = Debugger.snapshot(slug, event_limit: 500)

    catalog_updates =
      reloaded.debugger_timeline
      |> Enum.filter(fn row ->
        row.target == "phone" and
          ((row.type == "update" and row.message_source == "http") or
             (row.type == "runtime_exec_error" and
                String.contains?(to_string(row.message || ""), "CatalogReceived")))
      end)

    assert catalog_updates != [],
           "expected companion http follow-up from init Http.get, got: #{inspect(reloaded.debugger_timeline)}"

    assert Enum.any?(reloaded.events, fn event ->
             event.type == "debugger.package_cmd" and
               get_in(event, [:payload, :package]) == "elm/http" and
               String.contains?(get_in(event, [:payload, :response_message]) || "", "CatalogReceived")
           end)
  end


  test "tutorial watchface init emits platform and companion command events" do
    slug = "sim-tutorial-init-events-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_init_events",
        source_root: "watch"
      })

    timeline =
      reloaded.debugger_timeline
      |> Enum.sort_by(& &1.seq)
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert Enum.any?(timeline, fn
             {"watch", "BatteryLevelChanged " <> _, "init_device_data"} -> true
             _ -> false
           end)

    assert TimelineAssertions.has_entry?(timeline, "watch", "ConnectionStatusChanged", "init_device_data")

    assert Enum.any?(reloaded.events, fn event ->
             event.type in ["debugger.protocol_tx", "debugger.protocol_rx"]
           end)

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}
    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
    assert runtime_model["connected"] == %{"ctor" => "Just", "args" => [true]}
  end


  test "watch demo health template reports unsupported on aplite in debugger" do
    slug = "sim-watch-demo-health-aplite-#{System.unique_integer([:positive])}"

    source =
      File.read!(Path.join(["priv", "project_templates", "watch_demo_health", "src", "Main.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, _} = Debugger.set_watch_profile(slug, %{watch_profile_id: "aplite"})

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "watch_demo_health_aplite",
               source_root: "watch"
             })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert get_in(runtime_model, ["supported", "ctor"]) == "Just"
    assert get_in(runtime_model, ["supported", "args", Access.at(0)]) == false
    assert get_in(runtime_model, ["stepsNow", "ctor"]) == "Nothing"
    assert get_in(runtime_model, ["stepsToday", "ctor"]) == "Nothing"

    assert {:ok, compiled} =
             compile_health_template_preview(slug, source, reloaded.revision)

    view_output = get_in(compiled, [:watch, :model, "runtime_view_output"]) || []
    texts = for row <- view_output, row["kind"] == "text", do: row["text"]

    assert "Health API not supported on this watch" in texts
  end


  test "watch demo watch-info template loads device info in debugger" do
    slug = "sim-watch-demo-watch-info-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watch_demo_watch_info", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: source,
               reason: "watch_demo_watch_info",
               source_root: "watch"
             })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert get_in(runtime_model, ["model", "ctor"]) == "Just"
    assert get_in(runtime_model, ["color", "ctor"]) == "Just"
    assert get_in(runtime_model, ["firmware", "ctor"]) == "Just"
  end


  test "tutorial watchface request weather carries structured protocol payload" do
    slug = "sim-tutorial-weather-roundtrip-#{System.unique_integer([:positive])}"

    companion_source =
      File.read!(Path.expand("priv/pebble_app_template/src/elm/CompanionApp.elm", File.cwd!()))

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "src/CompanionApp.elm",
        source: companion_source,
        reason: "tutorial_companion_bootstrap",
        source_root: "phone"
      })

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: watch_source,
        reason: "tutorial_weather_roundtrip",
        source_root: "watch"
      })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, reloaded} = Debugger.snapshot(slug, event_limit: 500)

    protocol_events =
      reloaded.events
      |> Enum.filter(&(&1.type in ["debugger.protocol_tx", "debugger.protocol_rx"]))
      |> Enum.map(& &1.payload)

    assert Enum.any?(protocol_events, fn payload ->
             payload[:from] == "watch" and payload[:to] == "companion" and
               match?(
                 %{
                   "ctor" => "RequestWeather",
                   "args" => [%{"$ctor" => "CurrentLocation", "$args" => []}]
                 },
                 payload[:message_value]
               ) or
               match?(
                 %{
                   "ctor" => "RequestWeather",
                   "args" => [%{"ctor" => "CurrentLocation", "args" => []}]
                 },
                 payload[:message_value]
               )
           end)

    timeline =
      reloaded.debugger_timeline
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert TimelineAssertions.has_entry?(timeline, "phone", "FromWatch", "protocol_rx") or
             Enum.any?(protocol_events, fn payload ->
               payload[:from] == "watch" and payload[:to] == "companion"
             end)

    companion_runtime = get_in(reloaded, [:companion, :model, "runtime_model"]) || %{}
    assert companion_runtime["protocol_message_count"] == 1
    assert String.contains?(companion_runtime["protocol_last_inbound_message"], "RequestWeather")
    assert String.contains?(companion_runtime["protocol_last_inbound_message"], "CurrentLocation")
  end


  test "tutorial watchface minute subscription does not replay sibling device commands" do
    slug = "sim-tutorial-minute-no-sibling-device-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_minute_no_sibling_device",
        source_root: "watch"
      })

    reloaded_seq = reloaded.seq

    assert {:ok, triggered} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_minute_change",
               message: "MinuteChanged 17"
             })

    new_timeline =
      triggered.debugger_timeline
      |> Enum.filter(&(&1.raw_seq > reloaded_seq))
      |> Enum.map(&{&1.target, &1.message, &1.message_source})

    assert {"watch", "MinuteChanged 17", "subscription_trigger"} in new_timeline

    refute Enum.any?(new_timeline, fn
             {"watch", "BatteryLevelChanged " <> _, "device_data"} -> true
             {"watch", "ConnectionStatusChanged " <> _, "device_data"} -> true
             _ -> false
           end)
  end


  test "tutorial watchface normalizes runtime Maybe tuple for currentDateTime" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, TupleMaybeRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-tutorial-current-datetime-maybe-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_current_datetime_maybe",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert %{
             "ctor" => "Just",
             "args" => [
               %{
                 "year" => 2026,
                 "month" => 4,
                 "day" => 25,
                 "dayOfWeek" => %{"ctor" => "Sat", "args" => []},
                 "hour" => 21,
                 "minute" => 19,
                 "second" => 0,
                 "utcOffsetMinutes" => -360
               }
             ]
           } = runtime_model["currentDateTime"]
  end


  test "tutorial watchface hydrates battery Maybe when runtime reports nil" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, NilMaybeRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-tutorial-battery-nil-maybe-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_battery_nil_maybe",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}
    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
  end


  test "tutorial watchface normalizes optimized Maybe fields from runtime model contract" do
    previous_config = Application.get_env(:ide, Debugger, [])

    Application.put_env(
      :ide,
      Debugger,
      Keyword.put(previous_config, :runtime_executor_module, MaybeShapeRuntimeExecutor)
    )

    on_exit(fn -> Application.put_env(:ide, Debugger, previous_config) end)

    slug = "sim-tutorial-maybe-shapes-#{System.unique_integer([:positive])}"

    source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tutorial_complete", "src", "Main.elm"])
      )

    {:ok, _} = Debugger.start_session(slug)

    {:ok, reloaded} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: source,
        reason: "tutorial_maybe_shapes",
        source_root: "watch"
      })

    runtime_model = get_in(reloaded, [:watch, :model, "runtime_model"]) || %{}

    assert runtime_model["backgroundColor"] == %{"ctor" => "Nothing", "args" => []}
    assert runtime_model["batteryLevel"] == %{"ctor" => "Just", "args" => [88]}
    assert runtime_model["connected"] == %{"ctor" => "Just", "args" => [true]}

    assert runtime_model["condition"] == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Clear", "args" => []}]
           }

    assert runtime_model["temperature"] == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Celsius", "args" => [4]}]
           }
  end

end
