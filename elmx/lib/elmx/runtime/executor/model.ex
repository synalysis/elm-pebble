defmodule Elmx.Runtime.Executor.Model do
  @moduledoc false

  alias Elmx.Types

  @spec merge_runtime_model(Types.runtime_model(), Types.runtime_model()) :: Types.runtime_model()
  def merge_runtime_model(previous, model) when is_map(previous) and map_size(previous) > 0 do
    Map.merge(previous, model, fn _k, _prev, next -> next end)
  end

  def merge_runtime_model(_previous, model), do: model

  @spec runtime_model_from_elm(Types.runtime_model()) :: Types.runtime_model()
  def runtime_model_from_elm(model) when is_map(model) do
    Map.new(model, fn
      {k, %{"ctor" => _, "args" => _} = value} ->
        {to_string(k), from_elm_value(value)}

      {k, v} ->
        {to_string(k), from_elm_value(v)}
    end)
  end

  def runtime_model_from_elm(model), do: model

  @spec from_elm_value(Types.wire_value() | Types.elm_msg()) :: Types.elm_msg()
  def from_elm_value(%{"ctor" => "True", "args" => []}), do: true
  def from_elm_value(%{"ctor" => "False", "args" => []}), do: false

  def from_elm_value(%{"ctor" => ctor, "args" => args}) when is_list(args) do
    ctor_atom = String.to_atom(ctor)
    converted = Enum.map(args, &from_elm_value/1)

    case converted do
      [] -> ctor_atom
      [single] -> {ctor_atom, single}
      many -> List.to_tuple([ctor_atom | many])
    end
  end

  def from_elm_value(list) when is_list(list), do: Enum.map(list, &from_elm_value/1)

  def from_elm_value(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), from_elm_value(v)} end)
  end

  def from_elm_value({ctor, args}) when is_atom(ctor) and is_list(args) do
    converted = Enum.map(args, &from_elm_value/1)

    case converted do
      [] -> ctor
      [single] -> {ctor, single}
      many -> List.to_tuple([ctor | many])
    end
  end

  def from_elm_value(:True), do: true
  def from_elm_value(:False), do: false
  def from_elm_value(v), do: v
end
