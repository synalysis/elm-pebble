defmodule Elmc.Backend.Pebble.UiLabel do
  @moduledoc false

  # Display text for `Pebble.Ui.Label` constructors. Used only when encoding or
  # resolving that platform type — never from draw-command tags or app Msg names.

  @waiting_for_companion "Waiting for companion app"

  @constructors %{
    "Pebble.Ui.WaitingForCompanion" => @waiting_for_companion,
    "WaitingForCompanion" => @waiting_for_companion
  }

  @spec display_text(term()) :: String.t() | nil
  def display_text(name) when is_atom(name), do: display_text(Atom.to_string(name))

  def display_text(name) when is_binary(name) do
    Map.get(@constructors, name)
  end

  def display_text(_), do: nil

  @spec waiting_for_companion_text() :: String.t()
  def waiting_for_companion_text, do: @waiting_for_companion
end
