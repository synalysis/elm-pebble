defmodule Elmc.Backend.Pebble.IRAnalysis.RandomGenerate.Walker do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @random_generate_targets ["Random.generate", "Elm.Kernel.Random.generate"]

  @spec target_names(Types.ir_walk_node()) :: [Types.random_callback_candidate()]
  def target_names(%{op: :qualified_call, target: target, args: [to_msg, _generator]})
      when target in @random_generate_targets do
    callback_tagger_names(to_msg)
  end

  def target_names(%{} = node) do
    node
    |> Map.values()
    |> Enum.flat_map(&target_names/1)
  end

  def target_names(list) when is_list(list), do: Enum.flat_map(list, &target_names/1)
  def target_names(_), do: []

  @spec callback_tagger_names(Types.ir_walk_node()) :: [Types.random_callback_candidate()]
  def callback_tagger_names(%{op: :var, name: name}) when is_binary(name), do: [name]

  def callback_tagger_names(%{op: :int_literal, value: tag}) when is_integer(tag),
    do: [{:tag, tag}]

  def callback_tagger_names(%{op: :qualified_var, target: target}) when is_binary(target) do
    [target |> String.split(".") |> List.last()]
  end

  def callback_tagger_names(%{op: :qualified_call, target: target, args: []})
      when is_binary(target) do
    [target |> String.split(".") |> List.last()]
  end

  def callback_tagger_names(_), do: []
end
