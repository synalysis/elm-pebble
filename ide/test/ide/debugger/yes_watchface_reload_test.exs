defmodule Ide.Debugger.YesWatchfaceReloadTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadata

  test "companion CurrentTime step emits phone_to_watch protocol followups" do
    slug = "yes-current-time-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES CurrentTime",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    phone_root = Path.join(Projects.project_workspace_path(project), "phone")
    revision = "yes-current-time-#{slug}"

    assert {:ok, %{elmx_manifest: manifest}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(phone_root,
               revision: revision,
               entry_module: "CompanionApp"
             )

    assert {:ok, init_payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{},
               message: nil,
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    runtime_model = get_in(init_payload.model_patch, ["runtime_model"]) || %{}

    message_value = %{
      "ctor" => "CurrentTime",
      "args" => [
        %{"accuracy" => 25, "latitude" => 48.0, "longitude" => 10.0},
        1_782_640_957_905
      ]
    }

    assert {:ok, step_payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{"runtime_model" => runtime_model},
               message: "CurrentTime",
               message_value: message_value,
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    followups = Map.get(step_payload, :followup_messages) || []

    assert Enum.any?(followups, fn row ->
             Map.get(row, "package") == "companion-protocol" and
               Map.get(row, "message") == "ProvideTimezone"
           end),
           "expected ProvideTimezone protocol followup, got: #{inspect(followups, limit: 5)}"

    _ = Projects.delete_project(project)
  end

  test "CurrentPosition task chain produces ProvideTimezone followups" do
    slug = "yes-position-chain-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES Position",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    phone_root = Path.join(Projects.project_workspace_path(project), "phone")
    revision = "yes-position-chain-#{slug}"

    assert {:ok, %{elmx_manifest: manifest}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(phone_root,
               revision: revision,
               entry_module: "CompanionApp"
             )

    assert {:ok, init_payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{},
               message: nil,
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    runtime_model = get_in(init_payload.model_patch, ["runtime_model"]) || %{}
    location = %{"accuracy" => 25, "latitude" => 48.0, "longitude" => 10.0}

    assert {:ok, position_payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{"runtime_model" => runtime_model},
               message: "CurrentPosition",
               message_value: %{"ctor" => "Ok", "args" => [location]},
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    task_row =
      Enum.find(Map.get(position_payload, :followup_messages) || [], fn row ->
        Map.get(row, "message") == "CurrentTime"
      end)

    assert task_row != nil

    current_time_value = Map.get(task_row, "message_value")

    assert {:ok, current_time_payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: get_in(position_payload.model_patch, ["runtime_model"]) || %{},
               message: "CurrentTime",
               message_value: current_time_value,
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    followups = Map.get(current_time_payload, :followup_messages) || []

    assert Enum.any?(followups, fn row ->
             Map.get(row, "package") == "companion-protocol" and
               Map.get(row, "message") == "ProvideTimezone"
           end)

    _ = Projects.delete_project(project)
  end

  @tag timeout: 300_000
  test "yes watchface reload keeps companion preferences bridge and delivers timezone and weather" do
    slug = "yes-reload-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES Reload",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    root = Projects.project_workspace_path(project)
    watch_source = File.read!(Path.join([root, "watch", "src", "Main.elm"]))
    phone_source = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "yes_reload_watch"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "yes_reload_phone"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "latitude" => "48.0",
               "longitude" => "10.0",
               "accuracy" => "25.0"
             })

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 300)

    phone_errors =
      (state.debugger_timeline || [])
      |> Enum.filter(&(&1.type == "runtime_exec_error"))

    refute Enum.any?(phone_errors, fn row ->
             String.contains?(to_string(row.message || ""), "GeneratedPreferences")
           end),
           "phone reload must compile GeneratedPreferences: #{inspect(phone_errors)}"

    assert Enum.any?(state.debugger_timeline || [], fn row ->
             row.target == "phone" and
               is_binary(row.message) and String.starts_with?(row.message, "CurrentTime")
           end)

    current_time_errors =
      (state.debugger_timeline || [])
      |> Enum.filter(fn row ->
        row.type == "runtime_exec_error" and
          is_binary(row.message) and String.starts_with?(row.message, "CurrentTime")
      end)

    assert current_time_errors == [],
           "CurrentTime must not crash: #{inspect(current_time_errors)}"

    provide_weather_errors =
      (state.debugger_timeline || [])
      |> Enum.filter(fn row ->
        row.type == "runtime_exec_error" and
          is_binary(row.message) and String.contains?(row.message, "ProvideWeather")
      end)

    assert provide_weather_errors == [],
           "ProvideWeather must not crash: #{inspect(provide_weather_errors)}"

    fromwatch_errors =
      (state.debugger_timeline || [])
      |> Enum.filter(fn row ->
        row.type == "runtime_exec_error" and
          is_binary(row.message) and String.contains?(row.message, "FromWatch")
      end)

    assert fromwatch_errors == [],
           "FromWatch must not crash companion update: #{inspect(fromwatch_errors)}"

    assert Enum.any?(state.debugger_timeline || [], fn row ->
             row.target in ["phone", "companion"] and
               is_binary(row.message) and String.starts_with?(row.message, "GotWeather")
           end),
           "companion bridge must deliver GotWeather before watch protocol followups"

    provide_weather_row =
      (state.debugger_timeline || [])
      |> Enum.find(fn row ->
        row.target == "watch" and is_binary(row.message) and String.contains?(row.message, "ProvideWeather")
      end)

    watch_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert provide_weather_row != nil,
           "companion sendPhoneToWatch followups must deliver ProvideWeather to watch"

    assert provide_weather_row.message =~ "Celsius"
    public_watch_model = ModelMetadata.public_model(Map.get(state, :watch))

    assert is_integer(get_in(watch_model, ["layout", "screenW"])) and
             get_in(watch_model, ["layout", "screenW"]) > 0

    assert is_integer(get_in(watch_model, ["layout", "screenH"])) and
             get_in(watch_model, ["layout", "screenH"]) > 0
    assert get_in(watch_model, ["now", "ctor"]) == "Just"
    assert get_in(watch_model, ["batteryLevel", "ctor"]) == "Just"
    assert get_in(watch_model, ["connected", "ctor"]) == "Just"

    assert is_integer(get_in(public_watch_model, ["layout", "screenW"])) and
             get_in(public_watch_model, ["layout", "screenW"]) > 0
    assert get_in(public_watch_model, ["now", "ctor"]) == "Just"

    case get_in(watch_model, ["weather", "ctor"]) do
      "Just" ->
        [weather] = get_in(watch_model, ["weather", "args"])
        assert get_in(weather, ["temperature", "ctor"]) == "Celsius"

      other ->
        flunk("expected weather on watch model from elmx protocol followups, got: #{inspect(other)}")
    end

    watch_rows =
      (state.debugger_timeline || [])
      |> Enum.filter(&(&1.target == "watch"))
      |> Enum.map(& &1.message)

    assert Enum.any?(watch_rows, fn message ->
             is_binary(message) and String.contains?(message, "ProvideTimezone")
           end),
           "geolocation chain should deliver ProvideTimezone to watch: #{inspect(watch_rows)}"

    unknown_weather_rows =
      (state.debugger_timeline || [])
      |> Enum.filter(fn row ->
        row.target in ["phone", "companion"] and
          is_binary(row.message) and String.starts_with?(row.message, "Unknown")
      end)

    assert unknown_weather_rows == [],
           "weather bridge must not deliver Unknown callbacks: #{inspect(unknown_weather_rows)}"

    assert is_integer(watch_model["homeTzOffsetMin"])

    refute Map.has_key?(watch_model, "homeLatE6")

    public_companion_model = ModelMetadata.public_model(Map.get(state, :companion))
    refute Map.has_key?(public_companion_model, "screenW")
    refute Map.has_key?(public_companion_model, "screenH")

    view_type =
      get_in(state, [:watch, :view_tree, "type"]) || get_in(state, [:watch, :view_tree, :type])

    refute view_type == "previewUnavailable"

    _ = Projects.delete_project(project)
  end
end
