defmodule Ide.Debugger.Types.SimulatorSettings do
  @moduledoc """
  Canonical debugger simulator inputs (`Debugger.default_simulator_settings/0`,
  `normalize_simulator_settings/1`).

  Runtime maps use string keys; typespecs use atoms for Dialyzer (same fields).
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.StorageValue

  @type weather :: %{
          optional(:temperatureC) => integer(),
          optional(:condition) => String.t(),
          optional(:humidityPercent) => integer(),
          optional(:pressureHpa) => integer(),
          optional(:windKph) => integer(),
          optional(String.t()) => Types.wire_input()
        }

  @type environment :: %{
          optional(:sun) => map(),
          optional(:moon) => map(),
          optional(:tide) => map() | nil,
          optional(String.t()) => Types.wire_input()
        }

  @type t :: %{
          optional(:battery_percent) => integer(),
          optional(:charging) => boolean(),
          optional(:connected) => boolean(),
          optional(:clock_24h) => boolean(),
          optional(:use_simulated_time) => boolean(),
          optional(:simulated_time) => String.t() | nil,
          optional(:simulated_date) => String.t() | nil,
          optional(:timezone_id) => String.t(),
          optional(:timezone_offset_min) => integer(),
          optional(:locale) => String.t(),
          optional(:language) => String.t(),
          optional(:region) => String.t(),
          optional(:network_online) => boolean(),
          optional(:notifications_enabled) => boolean(),
          optional(:quiet_hours) => boolean(),
          optional(:weather) => weather(),
          optional(:calendar_events) => [map()],
          optional(:storage_values) => StorageValue.values_map(),
          optional(:preferences) => map(),
          optional(:environment) => environment(),
          optional(:latitude) => float(),
          optional(:longitude) => float(),
          optional(:accuracy) => float(),
          optional(:timeline_peek) => boolean(),
          optional(:compass_heading_deg) => integer(),
          optional(:compass_valid) => boolean(),
          optional(:app_in_focus) => boolean(),
          optional(:health_steps) => integer(),
          optional(:health_steps_today) => integer(),
          optional(:dictation_transcript) => String.t(),
          optional(:dictation_error) => String.t(),
          optional(:vibe_pattern_ms) => [integer()],
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
