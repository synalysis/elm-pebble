defmodule Elmc.TestSupport.TeaScenario do
  @moduledoc """
  elmc adapter over shared `Elmx.TeaPlaybook` playbooks.

  Playbooks are backend-neutral (wire steps + expects). This module projects them
  into the C host harness shape and filters steps by generated message capabilities
  (`ELMC_PEBBLE_HAS_MSG_*`, with fallbacks for legacy `#define ELMC_PEBBLE_MSG_*`
  / enum members).
  """

  alias Elmc.TestSupport.PlanStrictTemplates
  alias Elmx.TeaPlaybook

  @spec enabled_names() :: [String.t()]
  def enabled_names, do: TeaPlaybook.enabled_names()

  @spec for_template(String.t(), keyword()) :: map()
  def for_template(template, opts \\ []) do
    caps = capabilities(opts[:pebble_header_path])
    playbook = TeaPlaybook.for_template(template)

    steps =
      playbook
      |> TeaPlaybook.to_elmc_steps()
      |> filter_steps(caps)
      |> filter_protocol_steps(template)

    expects = filter_expects(playbook.expects || %{}, caps)

    %{
      mode: playbook.mode,
      needs_trig?: Map.get(playbook, :needs_trig?, false),
      steps: steps,
      expects: expects,
      playbook: playbook
    }
  end

  @doc """
  Returns a scenario map for every strict template (capability defaults only).
  """
  @spec all_template_scenarios(keyword()) :: %{String.t() => map()}
  def all_template_scenarios(opts \\ []) do
    Map.new(PlanStrictTemplates.names(), fn name ->
      {name, for_template(name, opts)}
    end)
  end

  @spec capabilities(String.t() | nil) :: map()
  def capabilities(nil), do: %{}

  def capabilities(header_path) when is_binary(header_path) do
    content = File.read!(header_path)

    %{
      has_current_datetime: msg?(content, "ELMC_PEBBLE_MSG_CURRENTDATETIME"),
      has_from_phone: msg?(content, "ELMC_PEBBLE_MSG_FROMPHONE"),
      has_battery: msg?(content, "ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED"),
      has_connection: msg?(content, "ELMC_PEBBLE_MSG_CONNECTIONCHANGED"),
      has_health: msg?(content, "ELMC_PEBBLE_MSG_GOTHEALTHSUPPORTED"),
      has_random: msg?(content, "ELMC_PEBBLE_MSG_RANDOMGENERATED"),
      has_storage: msg?(content, "ELMC_PEBBLE_MSG_STORAGEREADINT"),
      has_frame: String.contains?(content, "elmc_pebble_dispatch_frame"),
      has_direction_msgs:
        msg?(content, "ELMC_PEBBLE_MSG_LEFTPRESSED") and
          msg?(content, "ELMC_PEBBLE_MSG_RIGHTPRESSED"),
      buttons: button_steps(content)
    }
  end

  # Prefer `ELMC_PEBBLE_HAS_MSG_*` feature macros; fall back to legacy `#define MSG_*`
  # or enum members (`MSG_* = N`).
  defp msg?(content, "ELMC_PEBBLE_MSG_" <> suffix) do
    String.contains?(content, "#define ELMC_PEBBLE_HAS_MSG_#{suffix}") or
      String.contains?(content, "#define ELMC_PEBBLE_MSG_#{suffix}") or
      String.contains?(content, "ELMC_PEBBLE_MSG_#{suffix} =")
  end

  defp button_steps(content) do
    [
      {:up, "ELMC_PEBBLE_MSG_UPPRESSED"},
      {:down, "ELMC_PEBBLE_MSG_DOWNPRESSED"},
      {:select, "ELMC_PEBBLE_MSG_SELECTPRESSED"},
      {:back, "ELMC_PEBBLE_MSG_BACKPRESSED"},
      {:left, "ELMC_PEBBLE_MSG_LEFTPRESSED"},
      {:right, "ELMC_PEBBLE_MSG_RIGHTPRESSED"}
    ]
    |> Enum.filter(fn {_, macro} -> msg?(content, macro) end)
    |> Enum.map(fn {atom, _} -> {:dispatch_button, atom} end)
  end

  defp filter_protocol_steps(steps, template) do
    ctors =
      template
      |> Elmx.TeaPlaybook.Protocol.phone_to_watch_constructors()
      |> MapSet.new(& &1.name)

    Enum.filter(steps, fn
      {:from_phone, :provide_sun} -> MapSet.member?(ctors, "ProvideSun")
      {:from_phone, :provide_weather} -> MapSet.member?(ctors, "ProvideWeather")
      {:from_phone, :provide_condition} -> MapSet.member?(ctors, "ProvideCondition")
      {:from_phone, :provide_temperature} -> MapSet.member?(ctors, "ProvideTemperature")
      {:from_phone, :provide_moon_phase} -> MapSet.member?(ctors, "ProvideMoonPhase")
      {:from_phone, :provide_moon} -> MapSet.member?(ctors, "ProvideMoon")
      _ -> true
    end)
  end

  defp filter_steps(steps, caps) do
    Enum.filter(steps, fn
      {:dispatch_clock, _} -> caps[:has_current_datetime]
      {:from_phone, _} -> caps[:has_from_phone]
      {:dispatch_tag_value, :battery, _} -> caps[:has_battery]
      {:dispatch_tag_bool, :connection, _} -> caps[:has_connection]
      {:dispatch_tag_bool, :health, _} -> caps[:has_health]
      {:dispatch_tag_value, :random, _} -> caps[:has_random]
      {:cycle_msgs, :direction, _} -> caps[:has_direction_msgs]
      {:dispatch_button, _} -> caps[:buttons] != []
      _ -> true
    end)
  end

  defp filter_expects(expects, caps) do
    expects
    |> maybe_drop_expect(:no_placeholder_time?, caps[:has_current_datetime])
    |> maybe_drop_expect(:require_time_text?, caps[:has_current_datetime])
    |> maybe_drop_expect(:min_text_align_center, caps[:has_current_datetime])
    |> maybe_drop_expect(:min_text_full_width_center, caps[:has_current_datetime])
  end

  defp maybe_drop_expect(expects, key, keep?) do
    if keep?, do: expects, else: Map.delete(expects, key)
  end
end
