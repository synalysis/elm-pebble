defmodule Elmx.PebbleContractCmdSubTemplatesTest do
  @moduledoc """
  Per-template Cmd/Sub coverage against `Elmx.Pebble.Contract.CmdSub`.

  Scans every project template's Elm for contract call sites (with import aliases)
  and asserts TeaPlaybook steps exercise the template's primary Cmd/Sub surface —
  so demos are not left on the default button-only playbook forever.
  """

  use ExUnit.Case, async: true

  alias Elmx.Pebble.Contract.CmdSub
  alias Elmx.Pebble.Contract.TemplateCmdSubScan
  alias Elmx.TeaPlaybook

  @playbook_templates TeaPlaybook.enabled_names()

  test "every playbook template's Elm Cmd/Sub call sites are on the shared contract" do
    for template <- @playbook_templates do
      usage = TemplateCmdSubScan.usage(template)

      # Scanner only matches contract targets; unknown APIs would need contract rows.
      for target <- usage.targets do
        assert contract_target?(target),
               "#{template} uses #{target} but it is missing from CmdSub"
      end
    end
  end

  test "templates that use Cmd/Sub kinds get playbook steps that exercise them" do
    for template <- @playbook_templates do
      usage = TemplateCmdSubScan.usage(template)
      playbook = TeaPlaybook.for_template(template)
      steps = playbook.steps

      if :frame in usage.sub_ids do
        assert Enum.any?(steps, &(&1.op == :update and Map.get(&1, :action) == :frame)),
               "#{template} uses Frame.* but playbook has no :frame update"
      end

      if Enum.any?(usage.cmd_ids, &health_cmd?/1) or :health in usage.sub_ids do
        assert Enum.any?(steps, fn step ->
                 (step.op == :drain_cmds and :health in List.wrap(step[:kinds])) or
                   (step.op == :update and Map.get(step, :action) == :health)
               end),
               "#{template} uses Health Cmd/Sub but playbook never drains/dispatches health"
      end

      if Enum.any?(usage.cmd_ids, &time_cmd?/1) or
           Enum.any?(usage.sub_ids, &(&1 in [:second_change, :minute_change, :hour_change, :day_change])) do
        assert Enum.any?(steps, fn step ->
                 (step.op == :drain_cmds and :time in List.wrap(step[:kinds])) or
                   (step.op == :update and Map.get(step, :action) == :current_datetime)
               end),
               "#{template} uses time Cmd/Sub but playbook never drains/dispatches time"
      end

      if Enum.any?(usage.cmd_ids, &storage_cmd?/1) do
        assert Enum.any?(steps, fn step ->
                 step.op == :drain_cmds and :storage in List.wrap(step[:kinds])
               end),
               "#{template} uses Storage Cmd but playbook never drains :storage"
      end

      if :random_generate in usage.cmd_ids do
        assert Enum.any?(steps, fn step ->
                 (step.op == :drain_cmds and :random in List.wrap(step[:kinds])) or
                   (step.op == :update and Map.get(step, :action) == :random)
               end),
               "#{template} uses Random.generate but playbook never drains/dispatches random"
      end

      if :companion_send in usage.cmd_ids and String.starts_with?(template, "companion_demo_") do
        assert Enum.any?(steps, &(&1.op == :update and Map.get(&1, :action) == :from_phone)),
               "#{template} sends companion messages but playbook has no :from_phone step"
      end

      if effect_cmd?(usage.cmd_ids) do
        assert Enum.any?(steps, &(&1.op == :update and Map.get(&1, :action) == :button)),
               "#{template} issues effect cmds (vibes/light/speaker/…) but playbook has no button probe"
      end
    end
  end

  # Launch-context demo reads Platform.LaunchContext only (no Cmd/Sub surface).
  @cmd_sub_optional_demos MapSet.new(~w(watch_demo_launch))

  test "watch_demo templates each declare at least one contract Cmd or Sub" do
    demos =
      @playbook_templates
      |> Enum.filter(&String.starts_with?(&1, "watch_demo_"))
      |> Enum.reject(&MapSet.member?(@cmd_sub_optional_demos, &1))

    for template <- demos do
      usage = TemplateCmdSubScan.usage(template)

      assert usage.cmd_ids != [] or usage.sub_ids != [],
             "#{template} is an API demo but scanner found no Cmd/Sub contract targets"
    end
  end

  defp contract_target?(target) do
    Enum.any?(CmdSub.cmds() ++ CmdSub.subs(), fn row ->
      target in row.elm_targets
    end)
  end

  defp health_cmd?(id),
    do: id in [:health_supported, :health_value, :health_sum_today, :health_sum, :health_accessible]

  defp time_cmd?(id),
    do:
      id in [
        :get_current_date_time,
        :get_current_time_string,
        :get_clock_style_24h,
        :get_timezone,
        :get_timezone_is_set
      ]

  defp storage_cmd?(id),
    do:
      id in [
        :storage_write_int,
        :storage_read_int,
        :storage_delete,
        :storage_write_string,
        :storage_read_string,
        :storage_read_max_size
      ]

  defp effect_cmd?(ids) do
    Enum.any?(ids, fn id ->
      id in [
        :vibes_short_pulse,
        :vibes_long_pulse,
        :vibes_double_pulse,
        :vibes_custom_pattern,
        :vibes_cancel,
        :backlight,
        :speaker_play_tone,
        :speaker_play_notes,
        :speaker_play_tracks,
        :data_log_bytes,
        :data_log_int32,
        :dictation_start,
        :dictation_stop,
        :wakeup_schedule_after_seconds,
        :wakeup_cancel
      ]
    end)
  end
end
