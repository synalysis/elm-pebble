defmodule Ide.Debugger.RuntimeModelNormalize do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeModelHydrate
  alias Ide.Debugger.Types

  @type patch :: map()
  @type scalar_kind :: :string | :integer | :boolean

  @spec patch_values(Types.execution_model(), patch()) :: patch()
  def patch_values(model, patch) when is_map(model) and is_map(patch) do
    base_runtime_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        value when is_map(value) -> value
        _ -> %{}
      end

    initial_runtime_model = init_model(model)

    case Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model) do
      runtime_model when is_map(runtime_model) ->
        Map.put(
          patch,
          "runtime_model",
          model_values(base_runtime_model, runtime_model, initial_runtime_model)
        )

      _ ->
        patch
    end
  end

  def patch_values(_model, patch), do: patch

  @spec model_values(map(), map(), map()) :: map()
  defp model_values(previous, next, initial)
       when is_map(previous) and is_map(next) and is_map(initial) do
    Map.new(next, fn {key, value} ->
      previous_value = Map.get(previous, key)
      initial_value = Map.get(initial, key)
      shape = normalize_runtime_shape(previous_value, initial_value)
      {key, normalize_runtime_value(shape, value)}
    end)
    |> RuntimeModelHydrate.static_model_values()
  end

  @spec against_introspect(Types.inner_runtime_model(), Types.execution_model()) ::
          Types.inner_runtime_model()
  def against_introspect(runtime_model, model)
       when is_map(runtime_model) and is_map(model) do
    model_values(%{}, runtime_model, init_model(model))
  end

  def against_introspect(runtime_model, _model), do: runtime_model

  @spec init_model(Types.execution_model() | Types.app_model()) :: Types.init_model_values()
  def init_model(model) when is_map(model) do
    init_model =
      case RuntimeArtifacts.introspect(model) do
        %{"init_model" => value} when is_map(value) -> value
        _ -> nil
      end

    case init_model do
      value when is_map(value) -> RuntimeModelHydrate.static_model_values(value)
      _ -> %{}
    end
  end

  @spec normalize_runtime_shape(Types.protocol_wire_arg(), map()) :: map()
  defp normalize_runtime_shape(previous, initial) do
    cond do
      maybe_runtime_ctor?(previous) -> previous
      maybe_runtime_ctor?(initial) -> initial
      true -> previous
    end
  end

  @spec maybe_runtime_ctor?(Types.protocol_wire_arg()) :: boolean()
  defp maybe_runtime_ctor?(%{"ctor" => ctor, "args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: true

  defp maybe_runtime_ctor?(%{"$ctor" => ctor, "$args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: true

  defp maybe_runtime_ctor?(_value), do: false

  @spec normalize_runtime_value(Types.protocol_wire_normalize_input(), Types.protocol_wire_normalize_input()) ::
          Types.protocol_wire_arg()
  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, {1, value})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"ctor" => "Just", "args" => [normalize_runtime_value(nil, value)]}

  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args) and
              (is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value)) and
              value != 0,
       do: %{"ctor" => "Just", "args" => [value]}

  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args) and is_map(value) do
    if maybe_runtime_ctor?(value) do
      normalize_runtime_value(nil, value)
    else
      %{"ctor" => "Just", "args" => [normalize_runtime_value(nil, value)]}
    end
  end

  defp normalize_runtime_value(%{"ctor" => "Just", "args" => [_ | _]} = previous, %{
         "ctor" => "Nothing",
         "args" => []
       }),
       do: previous

  defp normalize_runtime_value(%{"ctor" => "Just", "args" => [_ | _]} = previous, nil),
    do: previous

  defp normalize_runtime_value(%{"ctor" => "Just", "args" => [_ | _]} = previous, 0),
    do: previous

  defp normalize_runtime_value(%{"ctor" => ctor, "args" => args}, 0)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"ctor" => "Nothing", "args" => []}

  defp normalize_runtime_value(%{"$ctor" => ctor, "$args" => args}, {1, value})
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"$ctor" => "Just", "$args" => [normalize_runtime_value(nil, value)]}

  defp normalize_runtime_value(%{"$ctor" => "Just", "$args" => [_ | _]} = previous, %{
         "$ctor" => "Nothing",
         "$args" => []
       }),
       do: previous

  defp normalize_runtime_value(%{"$ctor" => "Just", "$args" => [_ | _]} = previous, nil),
    do: previous

  defp normalize_runtime_value(%{"$ctor" => "Just", "$args" => [_ | _]} = previous, 0),
    do: previous

  defp normalize_runtime_value(%{"$ctor" => ctor, "$args" => args}, 0)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: %{"$ctor" => "Nothing", "$args" => []}

  defp normalize_runtime_value(previous, value) when is_map(previous) and is_map(value) do
    Map.new(value, fn {key, nested} ->
      {key, normalize_runtime_value(Map.get(previous, key), nested)}
    end)
  end

  defp normalize_runtime_value(_previous, value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, normalize_runtime_value(nil, nested)} end)
  end

  defp normalize_runtime_value(previous, values) when is_list(previous) and is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {value, idx} -> normalize_runtime_value(Enum.at(previous, idx), value) end)
  end

  defp normalize_runtime_value(_previous, values) when is_list(values),
    do: Enum.map(values, &normalize_runtime_value(nil, &1))

  defp normalize_runtime_value(_previous, %{"ctor" => "::", "args" => [head, tail]}),
    do: RuntimeModelHydrate.wire_list_to_elixir(%{"ctor" => "::", "args" => [head, tail]})

  defp normalize_runtime_value(_previous, %{"ctor" => "[]", "args" => []}), do: []

  defp normalize_runtime_value(shape, value),
    do: coerce_runtime_scalar(value, shape)

  @spec normalize_boolean(Types.wire_input(), boolean()) :: boolean()
  defp normalize_boolean(values, default) when is_list(values),
    do: Enum.any?(values, &normalize_boolean(&1, default))

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("True", _default), do: true
  defp normalize_boolean("False", _default), do: false
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(_value, default) when is_boolean(default), do: default

  @spec coerce_runtime_scalar(Types.wire_input(), Types.wire_input()) :: Types.wire_input()
  defp coerce_runtime_scalar(value, shape) do
    value =
      value
      |> RuntimeModelHydrate.static_value()
      |> unwrap_just_scalar(shape)
      |> coerce_char_list_string(shape)
      |> coerce_singleton_int_list(shape)

    cond do
      is_boolean(shape) -> normalize_boolean(value, shape)
      is_boolean(value) -> value
      true -> value
    end
  end

  @spec unwrap_just_scalar(Types.wire_input(), Types.wire_input()) :: Types.wire_input()
  defp unwrap_just_scalar(%{"ctor" => "Just", "args" => [inner]}, %{"ctor" => "Just", "args" => [_]}),
    do: %{"ctor" => "Just", "args" => [inner]}

  defp unwrap_just_scalar(%{"ctor" => "Just", "args" => [inner]}, %{ctor: "Just", args: [_]}),
    do: %{"ctor" => "Just", "args" => [inner]}

  defp unwrap_just_scalar(%{"ctor" => "Just", "args" => [inner]}, _shape), do: inner

  defp unwrap_just_scalar(value, _shape), do: value

  @spec coerce_char_list_string(Types.wire_input(), Types.wire_input()) :: Types.wire_input()
  defp coerce_char_list_string(value, shape) when is_binary(shape) and is_list(value) do
    if char_list_string?(value), do: List.to_string(value), else: value
  end

  defp coerce_char_list_string(value, _shape), do: value

  @spec coerce_singleton_int_list(Types.wire_input(), Types.wire_input()) :: Types.wire_input()
  defp coerce_singleton_int_list([n], shape) when is_integer(shape) and is_integer(n), do: n
  defp coerce_singleton_int_list(value, _shape), do: value

  @spec char_list_string?(Types.wire_input()) :: boolean()
  defp char_list_string?(list) do
    is_list(list) and
      list != [] and
      Enum.all?(list, &((is_integer(&1) and &1 >= 32 and &1 <= 126) or &1 == 9))
  end

end
