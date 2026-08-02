defmodule Elmx.TeaPlaybook do
  @moduledoc """
  Backend-neutral TEA playbooks shared by elmc host smokes and elmx/debugger tests.

  Steps are wire-compatible with the debugger Executor:

  - `op`: `:init` | `:drain_cmds` | `:update` | `:view` | `:subscriptions`
  - `action`: optional semantic action for platform adapters (`:current_datetime`,
    `:from_phone`, `:button`, `:frame`, …)
  - `message` / `message_value`: debugger wire fields when the Msg is known
  - `kinds`: for `:drain_cmds` (reply via `cmd` callback tags / followups — no Msg guessing)

  Use `to_json_map/1` / `from_json_map/1` to serialize the same playbook for both backends.
  """

  alias Elmx.TeaPlaybook.{Protocol, Samples}

  @type step_op :: :init | :drain_cmds | :update | :view | :subscriptions

  @type step :: %{
          required(:id) => String.t(),
          required(:op) => step_op(),
          optional(:action) => atom(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => term(),
          optional(:kinds) => [atom()],
          optional(:ctor) => String.t(),
          optional(:button) => atom(),
          optional(:value) => term(),
          optional(:count) => non_neg_integer(),
          optional(:dt_ms) => non_neg_integer()
        }

  @type t :: %{
          required(:template) => String.t(),
          required(:mode) => :watchface | :app,
          required(:steps) => [step()],
          required(:expects) => map(),
          optional(:needs_trig?) => boolean(),
          optional(:watch_profile_id) => String.t()
        }

  @enabled_templates ~w(
    watchface_digital
    watchface_minimal
    watchface_tangram_time
    watchface_smoke_screen
    watch_demo_time
    watchface_analog
    watchface_color_shapes
    watchface_yes
    game_2048
    game_elmtris
    watchface_weather_animated
  )

  @spec enabled_names() :: [String.t()]
  def enabled_names, do: @enabled_templates

  @spec for_template(String.t()) :: t()
  def for_template(template) when is_binary(template) do
    explicit = Map.get(overrides(), template)

    playbook =
      if is_map(explicit) do
        Map.merge(%{template: template, needs_trig?: needs_trig?(template)}, explicit)
      else
        default_playbook(template)
      end

    playbook
    |> Map.put_new(:watch_profile_id, "gabbro")
    |> Map.update!(:steps, &normalize_steps/1)
  end

  @doc """
  JSON-friendly map (string keys) for fixtures / cross-process use.
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(%{} = playbook) do
    %{
      "template" => playbook.template,
      "mode" => Atom.to_string(playbook.mode),
      "watch_profile_id" => Map.get(playbook, :watch_profile_id, "gabbro"),
      "needs_trig" => Map.get(playbook, :needs_trig?, false),
      "steps" => Enum.map(playbook.steps, &step_to_json/1),
      "expects" => expects_to_json(playbook.expects || %{})
    }
  end

  @spec from_json_map(map()) :: t()
  def from_json_map(%{} = map) do
    %{
      template: Map.fetch!(map, "template"),
      mode: String.to_existing_atom(Map.fetch!(map, "mode")),
      watch_profile_id: Map.get(map, "watch_profile_id", "gabbro"),
      needs_trig?: Map.get(map, "needs_trig", false),
      steps: Enum.map(Map.get(map, "steps", []), &step_from_json/1),
      expects: expects_from_json(Map.get(map, "expects", %{}))
    }
  end

  @doc """
  Project playbook steps into the elmc C-harness atom/tuple DSL.
  """
  @spec to_elmc_steps(t()) :: [term()]
  def to_elmc_steps(%{steps: steps}) do
    steps
    |> Enum.flat_map(&elmc_step/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Project playbook into elmx/debugger Executor steps (`op` + optional wire fields).
  `:drain_cmds` is preserved — runners apply followups from pending commands.
  """
  @spec to_elmx_steps(t()) :: [map()]
  def to_elmx_steps(%{steps: steps}) do
    Enum.map(steps, fn step ->
      step
      |> Map.take([
        :id,
        :op,
        :action,
        :message,
        :message_value,
        :kinds,
        :ctor,
        :button,
        :value,
        :count,
        :dt_ms
      ])
      |> maybe_fill_wire()
    end)
  end

  defp maybe_fill_wire(%{op: :update} = step) do
    case {Map.get(step, :message), Map.get(step, :message_value), Map.get(step, :action)} do
      {nil, nil, action} when not is_nil(action) ->
        {message, value} = wire_for_action(action, step)
        step |> Map.put(:message, message) |> Map.put(:message_value, value)

      {message, nil, action} when is_binary(message) and not is_nil(action) ->
        {_msg, value} = wire_for_action(action, step)
        Map.put(step, :message_value, value)

      _ ->
        step
    end
  end

  defp maybe_fill_wire(step), do: step

  defp wire_for_action(:current_datetime, _step), do: {"CurrentDateTime", Samples.current_datetime()}
  defp wire_for_action(:current_time_string, _step), do: {"CurrentTimeString", Samples.current_time_string()}
  defp wire_for_action(:battery, step), do: {"BatteryLevelChanged", Map.get(step, :value, 80)}
  defp wire_for_action(:connection, step), do: {"ConnectionChanged", Map.get(step, :value, true)}
  defp wire_for_action(:health, step), do: {"GotHealthSupported", Map.get(step, :value, true)}
  defp wire_for_action(:random, step), do: {"RandomGenerated", Map.get(step, :value, 42)}

  defp wire_for_action(:from_phone, step) do
    ctor = Map.get(step, :ctor) || raise("from_phone step requires :ctor")
    {"FromPhone", from_phone_value(ctor)}
  end

  defp wire_for_action(:button, step) do
    button = Map.get(step, :button) || :select
    {button_message(button), nil}
  end

  defp wire_for_action(:frame, step) do
    frame = Map.get(step, :value, 1)
    dt = Map.get(step, :dt_ms, 33)
    {"FrameTick", Samples.frame(frame, dt)}
  end

  defp wire_for_action(:direction, step) do
    button = Map.get(step, :button) || :left
    {button_message(button), nil}
  end

  defp wire_for_action(_action, _step), do: {nil, nil}

  defp from_phone_value("ProvideSun"), do: Samples.provide_sun()
  defp from_phone_value("ProvideWeather"), do: Samples.provide_weather()
  defp from_phone_value("ProvideCondition"), do: Samples.provide_condition()
  defp from_phone_value("ProvideTemperature"), do: Samples.provide_temperature()
  defp from_phone_value("ProvideMoonPhase"), do: Samples.provide_moon_phase()
  defp from_phone_value("ProvideMoon"), do: Samples.provide_moon()
  defp from_phone_value(ctor), do: Samples.from_phone(ctor, [])

  defp button_message(:up), do: "UpPressed"
  defp button_message(:down), do: "DownPressed"
  defp button_message(:left), do: "LeftPressed"
  defp button_message(:right), do: "RightPressed"
  defp button_message(:select), do: "SelectPressed"
  defp button_message(:back), do: "BackPressed"
  defp button_message(other) when is_atom(other), do: Macro.camelize(Atom.to_string(other))

  defp elmc_step(%{op: :init}), do: []
  defp elmc_step(%{op: :subscriptions}), do: []
  defp elmc_step(%{op: :view}), do: [:view]

  defp elmc_step(%{op: :drain_cmds, kinds: kinds}) do
    [{:drain_cmds, Enum.map(kinds, &ensure_atom/1)}]
  end

  defp elmc_step(%{op: :update, action: :current_datetime}), do: [{:dispatch_clock, :current_datetime}]
  defp elmc_step(%{op: :update, action: :battery, value: v}), do: [{:dispatch_tag_value, :battery, v}]
  defp elmc_step(%{op: :update, action: :connection, value: v}), do: [{:dispatch_tag_bool, :connection, v}]
  defp elmc_step(%{op: :update, action: :health, value: v}), do: [{:dispatch_tag_bool, :health, v}]
  defp elmc_step(%{op: :update, action: :random, value: v}), do: [{:dispatch_tag_value, :random, v}]

  defp elmc_step(%{op: :update, action: :from_phone, ctor: ctor}) do
    case ctor do
      "ProvideSun" -> [{:from_phone, :provide_sun}]
      "ProvideWeather" -> [{:from_phone, :provide_weather}]
      "ProvideCondition" -> [{:from_phone, :provide_condition}]
      "ProvideTemperature" -> [{:from_phone, :provide_temperature}]
      "ProvideMoonPhase" -> [{:from_phone, :provide_moon_phase}]
      "ProvideMoon" -> [{:from_phone, :provide_moon}]
      _ -> []
    end
  end

  defp elmc_step(%{op: :update, action: :button, button: button}), do: [{:dispatch_button, button}]

  defp elmc_step(%{op: :update, action: :direction_cycle, count: count}) do
    [{:cycle_msgs, :direction, count}]
  end

  defp elmc_step(%{op: :update, action: :frame, count: count, dt_ms: dt}) do
    [{:dispatch_frame, count, dt}]
  end

  defp elmc_step(%{op: :update, action: :frame} = step) do
    count = Map.get(step, :count, 1)
    dt = Map.get(step, :dt_ms, 33)
    [{:dispatch_frame, count, dt}]
  end

  defp elmc_step(_), do: []

  defp normalize_steps(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} ->
      step
      |> Map.put_new(:id, "step:#{idx}")
      |> Map.update(:op, :view, &ensure_atom/1)
      |> maybe_atomize(:action)
      |> maybe_atomize_list(:kinds)
    end)
  end

  defp maybe_atomize(step, key) do
    case Map.get(step, key) do
      value when is_binary(value) -> Map.put(step, key, String.to_existing_atom(value))
      _ -> step
    end
  rescue
    ArgumentError -> step
  end

  defp maybe_atomize_list(step, key) do
    case Map.get(step, key) do
      list when is_list(list) -> Map.put(step, key, Enum.map(list, &ensure_atom/1))
      _ -> step
    end
  end

  defp ensure_atom(value) when is_atom(value), do: value
  defp ensure_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp step_to_json(step) do
    step
    |> Map.new(fn
      {k, v} when is_atom(v) and k != :message_value -> {Atom.to_string(k), Atom.to_string(v)}
      {k, v} when is_list(v) and k == :kinds -> {Atom.to_string(k), Enum.map(v, &to_string/1)}
      {k, v} -> {Atom.to_string(k), v}
    end)
  end

  defp step_from_json(step) when is_map(step) do
    %{
      id: Map.get(step, "id", "step"),
      op: String.to_existing_atom(Map.fetch!(step, "op"))
    }
    |> maybe_put_atom(step, "action", :action)
    |> maybe_put(step, "message", :message)
    |> maybe_put(step, "message_value", :message_value)
    |> maybe_put_kinds(step)
    |> maybe_put(step, "ctor", :ctor)
    |> maybe_put_atom(step, "button", :button)
    |> maybe_put(step, "value", :value)
    |> maybe_put(step, "count", :count)
    |> maybe_put(step, "dt_ms", :dt_ms)
  end

  defp maybe_put(map, src, src_key, dest_key) do
    case Map.fetch(src, src_key) do
      {:ok, value} -> Map.put(map, dest_key, value)
      :error -> map
    end
  end

  defp maybe_put_atom(map, src, src_key, dest_key) do
    case Map.fetch(src, src_key) do
      {:ok, value} when is_binary(value) -> Map.put(map, dest_key, String.to_existing_atom(value))
      {:ok, value} when is_atom(value) -> Map.put(map, dest_key, value)
      _ -> map
    end
  rescue
    ArgumentError -> map
  end

  defp maybe_put_kinds(map, src) do
    case Map.fetch(src, "kinds") do
      {:ok, kinds} when is_list(kinds) -> Map.put(map, :kinds, Enum.map(kinds, &ensure_atom/1))
      _ -> map
    end
  end

  defp expects_to_json(expects) do
    Map.new(expects, fn {k, v} -> {to_string(k), v} end)
  end

  defp expects_from_json(expects) do
    Map.new(expects, fn {k, v} ->
      key =
        try do
          String.to_existing_atom(k)
        rescue
          ArgumentError -> String.to_atom(k)
        end

      {key, v}
    end)
  end

  defp needs_trig?(template) do
    template in ["watchface_yes", "watchface_weather_animated"] or
      Protocol.types_path(template) != nil
  end

  defp default_playbook(template) do
    mode = infer_mode(template)

    %{
      template: template,
      mode: mode,
      needs_trig?: needs_trig?(template),
      steps:
        [
          step_init(),
          step_drain([:time, :storage, :random])
        ] ++ phone_steps(template) ++ [step_view()],
      expects: %{min_scene_cmds: 1, min_view_rows: 1}
    }
  end

  defp phone_steps(template) do
    Protocol.phone_to_watch_constructors(template)
    |> Enum.flat_map(fn
      %{name: "ProvideSun"} -> [from_phone_step("ProvideSun")]
      %{name: "ProvideWeather"} -> [from_phone_step("ProvideWeather")]
      %{name: "ProvideCondition"} -> [from_phone_step("ProvideCondition")]
      %{name: "ProvideTemperature"} -> [from_phone_step("ProvideTemperature")]
      %{name: "ProvideMoonPhase"} -> [from_phone_step("ProvideMoonPhase")]
      %{name: "ProvideMoon"} -> [from_phone_step("ProvideMoon")]
      _ -> []
    end)
  end

  defp infer_mode(template) do
    if String.starts_with?(template, "watchface_"), do: :watchface, else: :app
  end

  defp overrides do
    %{
      "watchface_yes" => %{
        mode: :watchface,
        needs_trig?: true,
        steps: [
          step_init(),
          step_drain([:time]),
          update(:current_datetime, message: "CurrentDateTime"),
          update(:battery, value: 80, message: "BatteryLevelChanged"),
          update(:connection, value: true, message: "ConnectionChanged"),
          update(:health, value: true, message: "GotHealthSupported"),
          from_phone_step("ProvideSun"),
          from_phone_step("ProvideWeather"),
          from_phone_step("ProvideMoonPhase"),
          step_view()
        ],
        expects: %{
          min_scene_cmds: 2,
          min_scene_radial: 2,
          no_text_at_origin?: true,
          min_spy_text: 1,
          min_text_align_center: 1,
          min_text_full_width_center: 1,
          full_width_min: 100,
          min_view_rows: 1
        }
      },
      "game_2048" => %{
        mode: :app,
        steps: [
          step_init(),
          step_drain([:time, :storage, :random]),
          update(:random, value: 12_345, message: "RandomGenerated"),
          step_drain([:storage, :random]),
          %{id: "dirs", op: :update, action: :direction_cycle, count: 4},
          step_view()
        ],
        expects: %{min_scene_cmds: 4, min_scene_text: 1, min_view_rows: 1}
      },
      "game_elmtris" => %{
        mode: :app,
        steps: [
          step_init(),
          step_drain([:time, :storage, :random]),
          %{id: "frames", op: :update, action: :frame, count: 32, dt_ms: 33, message: "FrameTick"},
          step_view()
        ],
        expects: %{min_scene_cmds: 4, min_scene_text: 1, min_view_rows: 1}
      },
      "watchface_smoke_screen" => geometry_watchface(:fill_rect),
      "watchface_tangram_time" => geometry_watchface(:circle),
      "watchface_analog" => geometry_watchface(:circle),
      "watchface_color_shapes" => geometry_watchface(:circle),
      "watchface_weather_animated" => %{
        mode: :watchface,
        needs_trig?: true,
        steps: [
          step_init(),
          step_drain([:time]),
          update(:current_datetime, message: "CurrentDateTime"),
          from_phone_step("ProvideTemperature"),
          from_phone_step("ProvideCondition"),
          step_view()
        ],
        expects: %{min_scene_cmds: 1, min_view_rows: 1}
      },
      "watchface_digital" => %{
        mode: :watchface,
        steps: [
          step_init(),
          step_drain([:time]),
          step_view()
        ],
        expects: %{min_scene_cmds: 1, min_view_rows: 1, require_time_text?: true}
      },
      "watchface_minimal" => %{
        mode: :watchface,
        steps: [step_init(), step_drain([:time]), step_view()],
        expects: %{min_scene_cmds: 1, min_view_rows: 1}
      },
      "watch_demo_time" => %{
        mode: :watchface,
        steps: [step_init(), step_drain([:time]), step_view()],
        expects: %{min_scene_cmds: 1, min_view_rows: 1, require_time_text?: true}
      }
    }
  end

  defp geometry_watchface(:circle) do
    %{
      mode: :watchface,
      steps: [
        step_init(),
        step_drain([:time]),
        update(:current_datetime, message: "CurrentDateTime"),
        step_view()
      ],
      expects: %{min_scene_cmds: 1, min_scene_circle: 1, min_view_rows: 1}
    }
  end

  defp geometry_watchface(:fill_rect) do
    %{
      mode: :watchface,
      steps: [
        step_init(),
        step_drain([:time]),
        update(:current_datetime, message: "CurrentDateTime"),
        step_view()
      ],
      expects: %{
        min_scene_cmds: 1,
        min_scene_fill_rect: 1,
        min_spy_fill_rect: 1,
        min_view_rows: 1
      }
    }
  end

  defp step_init, do: %{id: "init", op: :init}
  defp step_view, do: %{id: "view", op: :view}

  defp step_drain(kinds) do
    %{id: "drain:#{Enum.join(kinds, ",")}", op: :drain_cmds, kinds: kinds}
  end

  defp update(action, opts) do
    %{id: "update:#{action}", op: :update, action: action}
    |> Map.merge(Map.new(opts))
  end

  defp from_phone_step(ctor) do
    %{
      id: "from_phone:#{ctor}",
      op: :update,
      action: :from_phone,
      ctor: ctor,
      message: "FromPhone",
      message_value: from_phone_value(ctor)
    }
  end
end
