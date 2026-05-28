defmodule Ide.Debugger.AutoFireMessageOrderTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.RuntimeHub

  @tangram_watch File.read!(
                   Path.join([
                     "priv",
                     "project_templates",
                     "watchface_tangram_time",
                     "src",
                     "Main.elm"
                   ])
                 )

  @tangram_phone File.read!(
                   Path.join([
                     "priv",
                     "project_templates",
                     "watchface_tangram_time",
                     "phone",
                     "src",
                     "CompanionApp.elm"
                   ])
                 )

  @weather_watch File.read!(
                   Path.join([
                     "priv",
                     "project_templates",
                     "watchface_weather_animated",
                     "src",
                     "Main.elm"
                   ])
                 )

  test "trigger_message_for_surface resolves minute-change payload for auto-fire" do
    slug = "auto-fire-trigger-msg-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, state} =
      Debugger.reload(slug, %{
        rel_path: "src/Main.elm",
        source: @tangram_watch,
        reason: "auto_fire_trigger_msg",
        source_root: "watch"
      })

    {:ok, state} =
      Debugger.set_simulator_settings(slug, %{
        "use_simulated_time" => true,
        "simulated_date" => "2026-05-27",
        "simulated_time" => "12:34:00",
        "timezone_offset_min" => 0
      })

    AgentSession.with_hosts(fn hosts ->
      contexts = RuntimeHub.contexts(hosts.hub)

      resolved =
        contexts.auto_fire.trigger_message.(state, :watch, "on_minute_change", "MinuteChanged")

      assert String.starts_with?(resolved, "MinuteChanged ")
      refute String.starts_with?(resolved, "CurrentDateTime")
    end)
  end

  test "tangram auto-fire does not log CurrentDateTime before MinuteChanged on watch" do
    slug = "auto-fire-tangram-order-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "src/Main.elm",
        source: @tangram_watch,
        reason: "auto_fire_tangram_order",
        source_root: "watch"
      })

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "src/CompanionApp.elm",
        source: @tangram_phone,
        reason: "auto_fire_tangram_phone",
        source_root: "phone"
      })

    {:ok, _} =
      Debugger.set_simulator_settings(slug, %{
        "use_simulated_time" => true,
        "simulated_date" => "2026-05-27",
        "simulated_time" => "23:58:30",
        "timezone_offset_min" => 0
      })

    {:ok, enabled} = Debugger.set_auto_fire(slug, %{target: "watch", enabled: "true"})
    baseline = enabled.debugger_seq
    Process.sleep(2_500)
    {:ok, stopped} = Debugger.stop_auto_tick(slug)

    watch_ctor_seqs =
      stopped.debugger_timeline
      |> Enum.filter(&(&1.seq > baseline and &1.target == "watch" and &1.type == "update"))
      |> Enum.map(fn row -> {row.seq, timeline_ctor(row.message)} end)

    minute_seq = seq_for_ctor(watch_ctor_seqs, "MinuteChanged")
    datetime_seq = seq_for_ctor(watch_ctor_seqs, "CurrentDateTime")

    assert minute_seq
    assert String.contains?(find_row_message(stopped, minute_seq), "MinuteChanged")

    if datetime_seq do
      assert minute_seq < datetime_seq
    end
  end

  test "weather animated auto-fire keeps MinuteChanged before CurrentDateTime when both appear" do
    slug = "auto-fire-weather-order-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source: @weather_watch,
        reason: "auto_fire_weather_order",
        source_root: "watch"
      })

    {:ok, _} =
      Debugger.set_simulator_settings(slug, %{
        "use_simulated_time" => true,
        "simulated_date" => "2026-05-27",
        "simulated_time" => "08:15:00",
        "timezone_offset_min" => 0
      })

    {:ok, enabled} = Debugger.set_auto_fire(slug, %{target: "watch", enabled: "true"})
    baseline = enabled.debugger_seq
    Process.sleep(2_500)
    {:ok, stopped} = Debugger.stop_auto_tick(slug)

    watch_ctor_seqs =
      stopped.debugger_timeline
      |> Enum.filter(&(&1.seq > baseline and &1.target == "watch" and &1.type == "update"))
      |> Enum.map(fn row -> {row.seq, timeline_ctor(row.message)} end)

    minute_seq = seq_for_ctor(watch_ctor_seqs, "MinuteChanged")
    datetime_seq = seq_for_ctor(watch_ctor_seqs, "CurrentDateTime")

    assert minute_seq

    if datetime_seq do
      assert minute_seq < datetime_seq
      assert String.contains?(find_row_message(stopped, datetime_seq), "CurrentDateTime")
    end
  end

  defp timeline_ctor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/[\s{]/, parts: 2)
    |> List.first()
    |> to_string()
  end

  defp timeline_ctor(_), do: ""

  defp seq_for_ctor(rows, ctor) do
    Enum.find_value(rows, fn {seq, name} -> if name == ctor, do: seq end)
  end

  defp find_row_message(%{debugger_timeline: timeline}, seq) do
    timeline
    |> Enum.find_value(fn row -> if row.seq == seq, do: row.message end)
    |> to_string()
  end
end
