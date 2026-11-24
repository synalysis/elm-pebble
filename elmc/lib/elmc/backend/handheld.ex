defmodule Elmc.Backend.Handheld do
  @moduledoc """
  Device registry for targets that use the handheld host.

  The compiler keys off the device id (`meowkit`, `flipper-zero`,
  `flipper-one`). `flipper` is the shared FAP package those Flipper devices
  emit. Pebble watch ids are not in this registry, so they keep the Pebble
  handlers. Add a device by adding one entry here.
  """

  @devices %{
    "meowkit" => :meowkit,
    "flipper-zero" => :flipper,
    "flipper-one" => :flipper,
    "flipper" => :flipper
  }

  @spec target?(keyword() | map() | nil) :: boolean()
  def target?(opts), do: targets(opts) != []

  @spec targets(keyword() | map() | nil) :: [String.t()]
  def targets(opts) when is_list(opts), do: opts |> Map.new() |> targets()

  def targets(opts) when is_map(opts) do
    opts
    |> Map.get(:target)
    |> ids()
    |> Enum.filter(&Map.has_key?(@devices, &1))
  end

  def targets(_), do: []

  @spec packages(keyword() | map() | nil) :: [:meowkit | :flipper]
  def packages(opts) do
    opts
    |> targets()
    |> Enum.map(&Map.fetch!(@devices, &1))
    |> Enum.uniq()
  end

  defp ids(target) when is_binary(target) do
    target
    |> String.split(~r/[, ]+/, trim: true)
    |> Enum.map(&String.downcase/1)
  end

  defp ids(target) when is_atom(target) and target != nil, do: [Atom.to_string(target)]
  defp ids(_), do: []
end
