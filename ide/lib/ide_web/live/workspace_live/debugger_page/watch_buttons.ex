defmodule IdeWeb.WorkspaceLive.DebuggerPage.WatchButtons do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPage.SubscriptionControls
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  alias IdeWeb.WorkspaceLive.DebuggerFlow.Types, as: FlowTypes

  @type trigger_row :: SupportTypes.trigger_button_row()
  @type watch_button :: :back | :up | :select | :down
  @type watch_button_control :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:trigger) => String.t(),
          required(:target) => String.t(),
          required(:message) => String.t(),
          required(:enabled) => boolean(),
          required(:title) => String.t()
        }

  @watch_buttons [:back, :up, :select, :down]

  @spec controls([trigger_row()], [FlowTypes.auto_fire_subscription_row()]) ::
          %{watch_button() => watch_button_control()}
  def controls(rows, disabled_subscriptions) when is_list(rows) do
    Map.new(@watch_buttons, fn button ->
      row = button_row(rows, button)
      {button, button_control(button, row, disabled_subscriptions)}
    end)
  end

  def controls(_rows, disabled_subscriptions),
    do: controls([], disabled_subscriptions)

  @spec button_control(
          watch_button(),
          trigger_row() | nil,
          [FlowTypes.auto_fire_subscription_row()]
        ) :: watch_button_control()
  defp button_control(button, row, disabled_subscriptions) when is_map(row) do
    enabled? =
      SubscriptionControls.enabled?(
        disabled_subscriptions,
        Map.get(row, :target) || Map.get(row, "target") || "watch",
        Map.get(row, :trigger) || Map.get(row, "trigger") || ""
      )

    %{
      id: Atom.to_string(button),
      label: button_label(button),
      trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
      target: Map.get(row, :target) || Map.get(row, "target") || "watch",
      message: Map.get(row, :message) || Map.get(row, "message"),
      enabled: enabled?,
      title: "Trigger #{button_label(button)} button event"
    }
  end

  defp button_control(button, _row, _disabled_subscriptions) do
    label = button_label(button)

    %{
      id: Atom.to_string(button),
      label: label,
      trigger: "",
      target: "watch",
      message: "",
      enabled: false,
      title: "#{label} button is not subscribed in this snapshot"
    }
  end

  @spec button_row([trigger_row()], watch_button()) :: trigger_row() | nil
  defp button_row(rows, button) when is_list(rows) do
    button_name = Atom.to_string(button)

    Enum.find(rows, &metadata_match?(&1, button_name, "pressed")) ||
      Enum.find(rows, &metadata_match?(&1, button_name, nil)) ||
      Enum.find(rows, &trigger_match?(&1, button_name))
  end

  @spec metadata_match?(trigger_row(), String.t(), String.t() | nil) :: boolean()
  defp metadata_match?(row, button_name, event_name) when is_map(row) do
    row_button = Map.get(row, :button) || Map.get(row, "button")
    row_event = Map.get(row, :button_event) || Map.get(row, "button_event")

    row_button == button_name and (is_nil(event_name) or row_event == event_name)
  end

  defp metadata_match?(_row, _button_name, _event_name), do: false

  @spec trigger_match?(trigger_row(), String.t()) :: boolean()
  defp trigger_match?(row, button_name) when is_map(row) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
    trigger in trigger_names(button_name)
  end

  defp trigger_match?(_row, _button_name), do: false

  @spec trigger_names(String.t()) :: [String.t()]
  defp trigger_names("back"), do: ["button_back", "on_button_back"]
  defp trigger_names("up"), do: ["button_up", "on_button_up"]
  defp trigger_names("select"), do: ["button_select", "on_button_select"]
  defp trigger_names("down"), do: ["button_down", "on_button_down"]
  defp trigger_names(_button), do: []

  @spec button_label(watch_button()) :: String.t()
  def button_label(:back), do: "Back"
  def button_label(:up), do: "Up"
  def button_label(:select), do: "Select"
  def button_label(:down), do: "Down"
end
