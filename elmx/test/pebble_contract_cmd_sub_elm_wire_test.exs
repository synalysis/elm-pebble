defmodule Elmx.PebbleContractCmdSubElmWireTest do
  @moduledoc """
  Same Elm surface fixture as elmc → elmx wire kinds and subscription masks.
  """

  use ExUnit.Case, async: false

  alias Elmx.Backend.QualifiedRewrite
  alias Elmx.Pebble.Contract.CmdSub
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.Subscriptions
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Pebble.SubscriptionMasks

  @surface_fixture Path.expand("../../elmc/test/fixtures/pebble_surface_project", __DIR__)

  @surface_sub_ids [
    :second_change,
    :hour_change,
    :minute_change,
    :day_change,
    :month_change,
    :year_change,
    :accel_tap,
    :battery,
    :connection,
    :frame,
    :button_raw,
    :accel_data,
    :app_focus,
    :compass,
    :dictation,
    :health,
    :animation_finished,
    :backlight,
    :screen_change,
    :speaker_finished,
    :unobstructed_area,
    :appmessage
  ]

  @primary_targets %{
    "Pebble.Cmd.timerAfter" => :timer_after_ms,
    "Pebble.Storage.writeInt" => :storage_write_int,
    "Pebble.Storage.readInt" => :storage_read_int,
    "Pebble.Storage.delete" => :storage_delete,
    "Companion.Watch.sendWatchToPhone" => :companion_send,
    "Pebble.Cmd.backlight" => :backlight,
    "Pebble.Time.currentTimeString" => :get_current_time_string,
    "Pebble.Time.currentDateTime" => :get_current_date_time,
    "Pebble.System.batteryLevel" => :get_battery_level,
    "Pebble.System.connectionStatus" => :get_connection_status,
    "Pebble.Storage.writeString" => :storage_write_string,
    "Pebble.Storage.readString" => :storage_read_string,
    "Random.generate" => :random_generate,
    "Pebble.Health.value" => :health_value,
    "Pebble.Health.supported" => :health_supported,
    "Pebble.Vibes.shortPulse" => :vibes_short_pulse,
    "Pebble.DataLog.logBytes" => :data_log_bytes,
    "Pebble.Compass.current" => :compass_peek,
    "Pebble.Dictation.start" => :dictation_start,
    "Pebble.UnobstructedArea.currentBounds" => :unobstructed_bounds_peek,
    "Pebble.Storage.maxSize" => :storage_read_max_size,
    "Pebble.Speaker.playTone" => :speaker_play_tone,
    "Pebble.Speaker.isMuted" => :speaker_is_muted,
    "Pebble.Speaker.stop" => :speaker_stop,
    "Pebble.Speaker.streamOpen" => :speaker_stream_open,
    "Pebble.Wakeup.scheduleAfterSeconds" => :wakeup_schedule_after_seconds,
    "Pebble.Log.infoCode" => :log_info_code
  }

  test "surface primary Elm targets rewrite to contract wire kinds" do
    for {target, id} <- @primary_targets do
      row = CmdSub.cmd!(id)
      args = conformance_args(target)

      rewrite_result =
        if target == "Random.generate" do
          QualifiedRewrite.rewrite(target, args)
        else
          SpecialValues.rewrite(target, args)
        end

      case row.elmx_wire do
        {:stub_none, _} ->
          assert {:ok, %{op: :cmd_none}} = rewrite_result

        _ ->
          assert {:ok, rewritten} = rewrite_result
          assert %{op: :runtime_call, function: fn_name} = rewritten

          wire = Pebble.runtime_dispatch(fn_name, runtime_args(rewritten.args))
          expected_kind = CmdSub.elmx_wire_kind(row.elmx_wire)

          case row.elmx_wire do
            {:effect, _family, variant} ->
              assert wire["kind"] == expected_kind
              assert wire["variant"] == variant

            {:dictation, _} ->
              assert wire["kind"] in ["cmd.dictation.followup", "batch"]

              if wire["kind"] == "batch" do
                assert Enum.any?(wire["commands"], &(&1["kind"] == expected_kind))
              end

            {:protocol, _} ->
              assert wire["kind"] in ["protocol", "batch"]

            _ ->
              assert wire["kind"] == expected_kind,
                     "#{target} wire kind expected #{expected_kind}, got #{inspect(wire["kind"])}"
          end
      end
    end
  end

  test "surface subscription Elm targets match contract mask bits" do
    for id <- @surface_sub_ids do
      row = CmdSub.sub!(id)

      primary =
        row.elm_targets
        |> Enum.find(fn t -> not String.starts_with?(t, "Elm.Kernel.") end)

      assert is_binary(primary), "no public Elm target for sub #{id}"

      mask =
        if id == :frame do
          Subscriptions.item_mask(%{
            op: :qualified_call,
            target: primary,
            args: [%{op: :int_literal, value: 33}, msg_tag()]
          })
        else
          SubscriptionMasks.mask(primary)
        end

      assert Bitwise.band(mask, row.bit) == row.bit,
             "sub #{id} mask #{mask} missing bit #{row.bit}"
    end
  end

  test "surface fixture compiles through elmx without dead-code stripping" do
    out_dir = Path.expand("tmp/elmx_surface_cmd_sub", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmx.compile(@surface_fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })
  end

  defp conformance_args("Pebble.Cmd.timerAfter"), do: [%{op: :int_literal, value: 1000}, msg_tag()]
  defp conformance_args("Pebble.Storage.writeInt"), do: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
  defp conformance_args("Pebble.Storage.readInt"), do: [%{op: :int_literal, value: 1}, msg_tag()]
  defp conformance_args("Pebble.Storage.delete"), do: [%{op: :int_literal, value: 1}]
  defp conformance_args("Companion.Watch.sendWatchToPhone"), do: [%{op: :int_literal, value: 0}]
  defp conformance_args("Pebble.Cmd.backlight"), do: [%{op: :int_literal, value: 2}]
  defp conformance_args("Pebble.Time.currentTimeString"), do: [msg_tag()]
  defp conformance_args("Pebble.Time.currentDateTime"), do: [msg_tag()]
  defp conformance_args("Pebble.System.batteryLevel"), do: [msg_tag()]
  defp conformance_args("Pebble.System.connectionStatus"), do: [msg_tag()]
  defp conformance_args("Pebble.Storage.writeString"), do: [%{op: :int_literal, value: 1}, %{op: :string_literal, value: "x"}]
  defp conformance_args("Pebble.Storage.readString"), do: [%{op: :int_literal, value: 1}, msg_tag()]
  defp conformance_args("Random.generate"),
    do: [msg_tag(), %{low: 1, high: 10}]
  defp conformance_args("Pebble.Health.value"), do: [%{op: :int_literal, value: 0}, msg_tag()]
  defp conformance_args("Pebble.Health.supported"), do: [msg_tag()]
  defp conformance_args("Pebble.Vibes.shortPulse"), do: []
  defp conformance_args("Pebble.DataLog.logBytes"), do: [%{op: :int_literal, value: 1}, %{op: :list_literal, value: []}]
  defp conformance_args("Pebble.Compass.current"), do: [msg_tag()]
  defp conformance_args("Pebble.Dictation.start"), do: []
  defp conformance_args("Pebble.UnobstructedArea.currentBounds"), do: [msg_tag()]
  defp conformance_args("Pebble.Storage.maxSize"), do: [msg_tag()]
  defp conformance_args("Pebble.Speaker.playTone"), do: [%{op: :int_literal, value: 440}, %{op: :int_literal, value: 100}, %{op: :int_literal, value: 80}, %{op: :int_literal, value: 0}]
  defp conformance_args("Pebble.Speaker.isMuted"), do: [msg_tag()]
  defp conformance_args("Pebble.Speaker.stop"), do: []
  defp conformance_args("Pebble.Speaker.streamOpen"), do: [%{op: :int_literal, value: 0}, %{op: :int_literal, value: 80}]
  defp conformance_args("Pebble.Wakeup.scheduleAfterSeconds"), do: [%{op: :int_literal, value: 60}]
  defp conformance_args("Pebble.Log.infoCode"), do: [%{op: :int_literal, value: 1}]
  defp conformance_args(_), do: [msg_tag()]

  defp msg_tag, do: %{op: :int_literal, union_ctor: "Tick", value: 0}

  defp runtime_args(args) when is_list(args), do: Enum.map(args, &runtime_arg/1)

  defp runtime_arg(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor),
    do: String.to_atom(ctor)

  defp runtime_arg(%{op: :int_literal, value: value}), do: value
  defp runtime_arg(%{op: :string_literal, value: value}), do: value
  defp runtime_arg(%{op: :list_literal, value: value}), do: value
  defp runtime_arg(other), do: other
end
