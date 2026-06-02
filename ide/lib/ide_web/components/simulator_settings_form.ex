defmodule IdeWeb.SimulatorSettingsForm do
  @moduledoc false
  use Phoenix.Component

  alias Ide.Projects.Project
  alias Ide.SimulatorSettings
  alias Ide.Debugger.Types
  alias Phoenix.LiveView.Rendered

  @type assigns :: map()
  @type rendered :: Rendered.t()

  attr :id, :string, required: true
  attr :project, Project, required: true
  attr :debugger_state, :map, default: nil
  attr :mode, :atom, default: :debugger
  attr :param_prefix, :string, default: "simulator"
  attr :change_event, :string, default: "simulator-save-settings"
  attr :class, :string, default: nil
  attr :description, :string, default: nil
  attr :group_columns, :integer, default: 2

  @spec simulator_settings_form(assigns()) :: rendered()
  def simulator_settings_form(assigns) do
    groups =
      SimulatorSettings.active_groups(assigns.project, assigns.debugger_state, assigns.mode)

    settings = SimulatorSettings.values_for(assigns.project, assigns.debugger_state)

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:settings, settings)
      |> assign(:empty?, groups == [])

    ~H"""
    <form
      id={@id}
      class={[
        "rounded border border-zinc-200 bg-white p-3 text-xs text-zinc-700",
        @class
      ]}
      phx-change={@change_event}
    >
      <div class="flex items-start justify-between gap-2">
        <div>
          <h3 class="text-sm font-semibold text-zinc-900">Simulator settings</h3>
          <p :if={@description} class="mt-1 text-[11px] text-zinc-500">{@description}</p>
          <p :if={!@description} class="mt-1 text-[11px] text-zinc-500">
            Saved automatically for this project. Only settings relevant to this app are shown.
          </p>
        </div>
      </div>

      <p
        :if={@empty?}
        class="mt-3 rounded border border-dashed border-zinc-200 bg-zinc-50 px-3 py-4 text-[11px] text-zinc-500"
      >
        No simulator controls apply to this project yet. Add watch or companion API usage in Elm to enable settings here.
      </p>

      <div
        :if={!@empty?}
        class={[
          "mt-3 grid min-w-0 gap-3",
          @group_columns == 1 && "grid-cols-1",
          @group_columns != 1 && "md:grid-cols-2"
        ]}
      >
        <div
          :for={{_group_id, title, fields} <- @groups}
          class="min-w-0 rounded border border-zinc-100 bg-zinc-50 p-2"
        >
          <h4 class="text-[11px] font-semibold uppercase tracking-wide text-zinc-500">{title}</h4>
          <div class="mt-2 space-y-2">
            <.field
              :for={field <- fields}
              field={field}
              settings={@settings}
              param_prefix={@param_prefix}
            />
          </div>
        </div>
      </div>
    </form>
    """
  end

  attr :field, :map, required: true
  attr :settings, :map, required: true
  attr :param_prefix, :string, required: true

  defp field(%{field: %{type: :range}} = assigns) do
    ~H"""
    <label class="block font-medium">
      {@field.label}
      <input
        name={input_name(@param_prefix, @field.key)}
        type="range"
        min={@field.min}
        max={@field.max}
        value={field_value(@settings, @field.key)}
        class="mt-1 w-full"
      />
      <span class="text-[11px] text-zinc-500">{field_value(@settings, @field.key)}%</span>
    </label>
    """
  end

  defp field(%{field: %{type: :checkbox}} = assigns) do
    ~H"""
    <input type="hidden" name={input_name(@param_prefix, @field.key)} value="false" />
    <label class="flex items-center gap-2 font-medium">
      <input
        name={input_name(@param_prefix, @field.key)}
        type="checkbox"
        value="true"
        checked={truthy?(field_value(@settings, @field.key))}
      />
      {@field.label}
    </label>
    <p :if={@field.hint} class="text-[11px] text-zinc-500">{@field.hint}</p>
    """
  end

  defp field(%{field: %{type: :date}} = assigns) do
    ~H"""
    <label class="block min-w-0 font-medium">
      {@field.label}
      <input
        name={input_name(@param_prefix, @field.key)}
        type="date"
        value={optional_string(field_value(@settings, @field.key))}
        class="mt-1 w-full min-w-0 max-w-full rounded border border-zinc-300 bg-white px-2 py-1"
      />
    </label>
    """
  end

  defp field(%{field: %{type: :time}} = assigns) do
    ~H"""
    <label class="block min-w-0 font-medium">
      {@field.label}
      <input
        name={input_name(@param_prefix, @field.key)}
        type="time"
        step="1"
        value={optional_string(field_value(@settings, @field.key))}
        class="mt-1 w-full min-w-0 max-w-full rounded border border-zinc-300 bg-white px-2 py-1"
      />
    </label>
    """
  end

  defp field(%{field: %{type: :select}} = assigns) do
    ~H"""
    <label class="block font-medium">
      {@field.label}
      <select
        name={input_name(@param_prefix, @field.key)}
        class="mt-1 w-full rounded border border-zinc-300 bg-white px-2 py-1"
      >
        <option
          :for={{value, label} <- @field.options || []}
          value={value}
          selected={field_value(@settings, @field.key) == value}
        >
          {label}
        </option>
      </select>
    </label>
    """
  end

  defp field(%{field: %{type: :json}} = assigns) do
    ~H"""
    <label class="block font-medium">
      {@field.label}
      <textarea
        name={input_name(@param_prefix, @field.key)}
        rows="4"
        class="mt-1 w-full rounded border border-zinc-300 bg-white px-2 py-1 font-mono text-[11px]"
      >{optional_string(field_value(@settings, @field.key))}</textarea>
    </label>
    <p :if={@field.hint} class="text-[11px] text-zinc-500">{@field.hint}</p>
    """
  end

  defp field(assigns) do
    ~H"""
    <label class="block font-medium">
      {@field.label}
      <input
        name={input_name(@param_prefix, @field.key)}
        type={input_type(@field.type)}
        min={@field.min}
        max={@field.max}
        step={@field.step}
        value={field_value(@settings, @field.key)}
        class="mt-1 w-full rounded border border-zinc-300 bg-white px-2 py-1"
      />
    </label>
    <p :if={@field.hint} class="text-[11px] text-zinc-500">{@field.hint}</p>
    """
  end

  @spec input_name(String.t(), String.t()) :: String.t()
  defp input_name(prefix, key), do: "#{prefix}[#{key}]"

  @spec input_type(atom()) :: String.t()
  defp input_type(:number), do: "number"
  defp input_type(_), do: "text"

  @spec field_value(map(), String.t()) :: Types.wire_input() | nil
  defp field_value(settings, key) when is_map(settings), do: Map.get(settings, key)

  @spec optional_string(Types.wire_scalar() | list() | map()) :: String.t()
  defp optional_string(value) when is_binary(value), do: value
  defp optional_string(nil), do: ""
  defp optional_string(value) when is_number(value), do: to_string(value)
  defp optional_string(value) when is_boolean(value), do: to_string(value)
  defp optional_string(_), do: ""

  @spec truthy?(Types.wire_scalar()) :: boolean()
  defp truthy?(value) when value in [true, "true", "True", "on", "1", 1], do: true
  defp truthy?(_value), do: false
end
