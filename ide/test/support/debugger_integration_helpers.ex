defmodule Ide.DebuggerIntegrationHelpers do
  @moduledoc false

  import ExUnit.Assertions

  def assert_replay_telemetry(payload, expected) when is_map(payload) and is_map(expected) do
    telemetry = Map.get(payload, :replay_telemetry)
    assert is_map(telemetry)
    assert telemetry.mode == expected.mode
    assert telemetry.source == expected.source
    assert telemetry.drift_seq == expected.drift_seq
    assert telemetry.drift_band == expected.drift_band
    assert telemetry.used_live_query == expected.used_live_query
    assert telemetry.used_frozen_preview == expected.used_frozen_preview
  end
  def compile_health_template_preview(slug, source, revision) do
    workspace_root =
      Path.join([
        System.tmp_dir!(),
        "watch_demo_health_preview_#{System.unique_integer([:positive])}"
      ])

    assert :ok = Ide.ProjectTemplates.apply_template("watch-demo-health", workspace_root)
    File.write!(Path.join(workspace_root, "watch/src/Main.elm"), source)

    assert {:ok, compile_result} =
             Ide.Compiler.compile("watch-demo-health-preview-#{slug}",
               workspace_root: workspace_root
             )

    assert compile_result.status == :ok

    Ide.Debugger.ingest_elmc_compile(slug, %{
      status: :ok,
      compiled_path: "watch",
      revision: revision || "health-preview",
      elm_executor_core_ir_b64: compile_result.elm_executor_core_ir_b64,
      elm_executor_metadata: compile_result.elm_executor_metadata || %{}
    })
  end

  def collect_view_text(node) when is_map(node) do
    own =
      case node["text"] || node[:text] do
        text when is_binary(text) -> [text]
        _ -> []
      end

    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> Enum.flat_map(list, &collect_view_text/1)
        _ -> []
      end

    own ++ children
  end

  def collect_view_text(_), do: []

  def weather_condition_matches?(value, wire_code, ctor_name) do
    match?(%{"ctor" => "Just", "args" => [^wire_code]}, value) or
      match?(%{"ctor" => "Just", "args" => [%{"ctor" => ^ctor_name, "args" => []}]}, value)
  end

  def weather_preview_label(%{} = runtime_model) do
    temperature = runtime_model["temperature"]
    condition = runtime_model["condition"]

    cond_label =
      case condition do
        %{"ctor" => "Just", "args" => [code]} when is_integer(code) ->
          weather_ctor_label(code)

        %{"ctor" => "Just", "args" => [%{"ctor" => ctor, "args" => []}]} when is_binary(ctor) ->
          ctor

        _ ->
          nil
      end

    case {temperature, cond_label} do
      {%{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [temp]}]}, label}
      when is_integer(temp) and is_binary(label) and label != "" ->
        "#{temp}C #{label}"

      _ ->
        nil
    end
  end

  def weather_ctor_label(1), do: "Clear"
  def weather_ctor_label(2), do: "Cloudy"
  def weather_ctor_label(4), do: "Drizzle"
  def weather_ctor_label(5), do: "Rain"
  def weather_ctor_label(6), do: "Snow"
  def weather_ctor_label(_), do: "Weather"

  def weather_preview_label(_), do: nil

  def wait_until_stable_minute do
    if NaiveDateTime.local_now().second > 50 do
      Process.sleep(1_000)
      wait_until_stable_minute()
    else
      :ok
    end
  end

  def synthetic_step_protocol_event?(%{type: type, payload: payload})
       when type in ["debugger.protocol_tx", "debugger.protocol_rx"] and is_map(payload) do
    message = Map.get(payload, :message) || Map.get(payload, "message") || ""
    trigger = Map.get(payload, :trigger) || Map.get(payload, "trigger")

    is_binary(message) and String.starts_with?(message, "Step:") and
      trigger in ["step", "tick", "replay"]
  end

  def synthetic_step_protocol_event?(_), do: false

  def collect_view_nodes(node) when is_map(node) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> list
        _ -> []
      end

    [node | Enum.flat_map(children, &collect_view_nodes/1)]
  end

  def collect_view_nodes(_node), do: []
end
