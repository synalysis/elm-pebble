defmodule Ide.WatchModels do
  @moduledoc """
  Canonical watch model catalog used across debugger and emulator flows.
  """

  @ordered_ids ~w(aplite basalt chalk diorite emery flint gabbro)

  @profiles %{
    "aplite" => %{
      "name" => "Aplite",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168, "is_color" => false}
    },
    "basalt" => %{
      "name" => "Basalt",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168, "is_color" => true}
    },
    "chalk" => %{
      "name" => "Chalk",
      "shape" => "round",
      "screen" => %{"width" => 180, "height" => 180, "is_color" => true}
    },
    "diorite" => %{
      "name" => "Diorite",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168, "is_color" => false}
    },
    "emery" => %{
      "name" => "Emery",
      "shape" => "rect",
      "screen" => %{"width" => 200, "height" => 228, "is_color" => true}
    },
    "flint" => %{
      "name" => "Flint",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168, "is_color" => true}
    },
    "gabbro" => %{
      "name" => "Gabbro",
      "shape" => "round",
      "screen" => %{"width" => 180, "height" => 180, "is_color" => true}
    }
  }

  @spec ordered_ids() :: [String.t()]
  def ordered_ids, do: @ordered_ids

  @spec default_id() :: String.t()
  def default_id, do: "basalt"

  @spec profiles_map() :: map()
  def profiles_map, do: @profiles

  @spec profile_for(String.t() | nil) :: map()
  def profile_for(id) when is_binary(id) do
    normalized = String.downcase(String.trim(id))
    Map.get(@profiles, normalized, Map.fetch!(@profiles, default_id()))
  end

  def profile_for(_), do: Map.fetch!(@profiles, default_id())
end
