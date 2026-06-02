defmodule Ide.Debugger.RuntimeModelHydrate do
  @moduledoc ""

  alias Ide.Debugger.RuntimeModelQuality
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.Types

  @type skip_fields :: [String.t()]

  @message_constructor_runtime_fields %{
    "CurrentTimeString" => ["timeString"],
    "CurrentTime" => ["timeString"],
    "CurrentDateTime" => ["currentDateTime"],
    "BatteryLevelChanged" => ["batteryLevel", "batteryPercent"],
    "ConnectionStatusChanged" => ["connected", "online"]
  }

  defp hydrate_runtime_model_message_payload(runtime_model, message, skip_fields)
       when is_map(runtime_model) and is_binary(message) and is_list(skip_fields) do
    constructor = RuntimeModelMessages.wire_constructor(message)
    payload = elm_message_payload(message)

    cond do
      not is_nil(payload) ->
        maybe_put_message_payload_field(runtime_model, constructor, payload, skip_fields)

      true ->
        runtime_model
    end
  end

  defp hydrate_runtime_model_message_payload(runtime_model, _message, _skip_fields)
       when is_map(runtime_model),
       do: runtime_model

  @spec elm_message_payload(String.t()) :: Types.protocol_wire_arg() | nil
  defp elm_message_payload(message) when is_binary(message) do
    case String.split(String.trim(message), ~r/\s+/, parts: 2) do
      [_ctor, payload] -> elm_literal_payload(String.trim(payload))
      _ -> nil
    end
  end

  @spec elm_literal_payload(String.t()) :: Types.protocol_wire_arg() | nil
  defp elm_literal_payload(""), do: nil
  defp elm_literal_payload("True"), do: true
  defp elm_literal_payload("False"), do: false

  defp elm_literal_payload(payload) when is_binary(payload) do
    cond do
      String.match?(payload, ~r/^-?\d+$/) ->
        case Integer.parse(payload) do
          {value, ""} -> value
          _ -> nil
        end

      String.starts_with?(payload, "{") or String.starts_with?(payload, "[") or
          String.starts_with?(payload, "\"") ->
        case Jason.decode(payload) do
          {:ok, value} -> value
          _ -> nil
        end

      true ->
        nil
    end
  end

  @spec maybe_put_message_payload_field(
          Types.runtime_model_patch(),
          String.t(),
          Types.protocol_wire_arg(),
          [String.t()]
        ) :: Types.runtime_model_patch()
  defp maybe_put_message_payload_field(runtime_model, constructor, payload, skip_fields)
       when is_map(runtime_model) and is_binary(constructor) and is_list(skip_fields) do
    case model_field_for_message_constructor(constructor, runtime_model) do
      field when is_binary(field) ->
        if field in skip_fields do
          runtime_model
        else
          if Map.has_key?(runtime_model, field) do
            put_payload_value_if_needed(runtime_model, field, payload, constructor)
          else
            runtime_model
          end
        end

      _ ->
        runtime_model
    end
  end

  defp maybe_put_message_payload_field(runtime_model, _constructor, _payload, _skip_fields),
    do: runtime_model

  @spec model_field_for_message_constructor(String.t(), Types.inner_runtime_model() | nil) ::
          String.t() | nil
  defp model_field_for_message_constructor(constructor, runtime_model)

  defp model_field_for_message_constructor("Got" <> rest, _runtime_model),
    do: lower_camel_name(rest)

  defp model_field_for_message_constructor(constructor, runtime_model)
       when is_binary(constructor) do
    case Map.get(@message_constructor_runtime_fields, constructor, []) do
      [] ->
        nil

      candidates ->
        pick_existing_runtime_field(candidates, runtime_model)
    end
  end

  @spec pick_existing_runtime_field([String.t()], Types.inner_runtime_model() | nil) ::
          String.t() | nil
  defp pick_existing_runtime_field(candidates, runtime_model) when is_list(candidates) do
    Enum.find(candidates, fn key ->
      is_map(runtime_model) and Map.has_key?(runtime_model, key)
    end) || List.first(candidates)
  end

  @spec put_payload_value_if_needed(
          Types.runtime_model_patch(),
          String.t(),
          Types.protocol_wire_arg(),
          String.t()
        ) :: Types.runtime_model_patch()
  defp put_payload_value_if_needed(runtime_model, key, value, constructor)
       when is_map(runtime_model) and is_binary(key) do
    case Map.get(runtime_model, key) do
      %{"ctor" => ctor, "args" => args} when ctor in ["Nothing", "Just"] and is_list(args) ->
        Map.put(runtime_model, key, %{"ctor" => "Just", "args" => [value]})

      %{"$ctor" => ctor, "$args" => args} when ctor in ["Nothing", "Just"] and is_list(args) ->
        Map.put(runtime_model, key, %{"$ctor" => "Just", "$args" => [value]})

      nil ->
        Map.put(runtime_model, key, %{"ctor" => "Just", "args" => [value]})

      current ->
        if message_constructor_value?(current, constructor),
          do: Map.put(runtime_model, key, value),
          else: runtime_model
    end
  end

  @spec lower_camel_name(String.t()) :: String.t() | nil
  defp lower_camel_name(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  defp lower_camel_name(_), do: nil

  @spec for_message(Types.app_model(), String.t() | nil, skip_fields()) :: Types.app_model()
  def for_message(model, message, skip_fields)
      when is_map(model) and is_list(skip_fields) do
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)

    if is_map(runtime_model) do
      hydrated =
        runtime_model
        |> hydrate_static_runtime_model_values()
        |> hydrate_runtime_model_launch_context(model)
        |> hydrate_runtime_model_message_payload(message, skip_fields)

      Map.put(model, "runtime_model", RuntimeModelQuality.drop_parser_artifacts(hydrated))
    else
      model
    end
  end

  def for_message(model, _message, _skip_fields) when is_map(model), do: model
  @spec patched_fields(Types.app_model()) :: skip_fields()
  def patched_fields(patch) when is_map(patch) do
    case Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model) do
      runtime_model when is_map(runtime_model) -> Enum.map(Map.keys(runtime_model), &to_string/1)
      _ -> []
    end
  end

  @spec static_model_values(Types.inner_runtime_model()) :: Types.inner_runtime_model()
  def static_model_values(runtime_model) when is_map(runtime_model),
    do: hydrate_static_runtime_model_values(runtime_model)

  def static_model_values(runtime_model), do: runtime_model

  @spec static_value(Types.wire_input()) :: Types.wire_input()
  def static_value(value), do: hydrate_static_runtime_value(value)

  @spec wire_list_to_elixir(Types.protocol_ctor_value() | list()) :: list()
  def wire_list_to_elixir(value), do: elm_list_wire_to_elixir(value)

  @spec normalize_boolean_string(String.t()) :: boolean() | String.t()
  def normalize_boolean_string(value) when is_binary(value),
    do: normalize_runtime_boolean_string(value)

  @spec hydrate_static_runtime_model_values(Types.inner_runtime_model()) ::
          Types.inner_runtime_model()
  defp hydrate_static_runtime_model_values(runtime_model) when is_map(runtime_model) do
    runtime_model
    |> Enum.map(fn {key, value} ->
      case hydrate_static_runtime_value(value) do
        nil -> nil
        hydrated -> {key, hydrated}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp hydrate_static_runtime_model_values(runtime_model), do: runtime_model

  @spec hydrate_static_runtime_value(Types.wire_input()) :: Types.wire_input()
  defp hydrate_static_runtime_value(%{} = value) do
    cond do
      Map.has_key?(value, "$ctor") ->
        ctor = to_string(Map.get(value, "$ctor") || "")
        args = Map.get(value, "$args") || []
        hydrate_constructor_value(ctor, args)

      Map.has_key?(value, "ctor") ->
        ctor = to_string(Map.get(value, "ctor") || "")
        args = Map.get(value, "args") || []
        hydrate_constructor_value(ctor, args)

      Map.has_key?(value, "$call") ->
        call = to_string(Map.get(value, "$call") || "")
        args = Map.get(value, "$args") || []
        args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

        case static_color_call_value(call, args) do
          {:ok, color} -> color
          :error -> nil
        end

      Map.has_key?(value, "call") or Map.has_key?(value, :call) ->
        nil

      true ->
        Map.new(value, fn {key, nested} -> {key, hydrate_static_runtime_value(nested)} end)
    end
  end

  defp hydrate_static_runtime_value(values) when is_list(values),
    do: Enum.map(values, &hydrate_static_runtime_value/1)

  defp hydrate_static_runtime_value(value) when is_binary(value),
    do: normalize_runtime_boolean_string(value)

  defp hydrate_static_runtime_value(value) when is_boolean(value), do: value
  defp hydrate_static_runtime_value(value), do: value

  @spec hydrate_constructor_value(String.t(), list()) :: Types.wire_input()
  defp hydrate_constructor_value(ctor, args) when is_binary(ctor) do
    args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

    case {ctor, args} do
      {"True", []} -> true
      {"False", []} -> false
      {"[]", []} -> []
      {"::", [head, tail]} -> [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
      _ -> %{"ctor" => ctor, "args" => args}
    end
  end

  @spec elm_list_wire_to_elixir(Types.protocol_ctor_value() | list()) :: list()
  defp elm_list_wire_to_elixir([]), do: []

  defp elm_list_wire_to_elixir(%{"ctor" => "[]", "args" => []}), do: []

  defp elm_list_wire_to_elixir(%{"ctor" => "::", "args" => [head, tail]}) do
    [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
  end

  defp elm_list_wire_to_elixir(%{ctor: "[]", args: []}), do: []

  defp elm_list_wire_to_elixir(%{ctor: "::", args: [head, tail]}) do
    [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
  end

  defp elm_list_wire_to_elixir(list) when is_list(list),
    do: Enum.map(list, &hydrate_static_runtime_value/1)

  defp elm_list_wire_to_elixir(value), do: [hydrate_static_runtime_value(value)]

  @spec normalize_runtime_boolean_string(String.t()) :: boolean() | String.t()
  defp normalize_runtime_boolean_string(value) when is_binary(value) do
    case String.trim(value) do
      "True" -> true
      "False" -> false
      "true" -> true
      "false" -> false
      other -> other
    end
  end

  @spec static_color_call_value(String.t(), list()) :: {:ok, integer()} | :error
  defp static_color_call_value(call, []) when is_binary(call) do
    normalized = String.downcase(call)
    name = normalized |> String.split(".") |> List.last() |> to_string()

    cond do
      String.contains?(normalized, "color") ->
        static_color_constant(name)

      true ->
        :error
    end
  end

  defp static_color_call_value(_call, _args), do: :error

  @spec static_color_constant(String.t()) :: {:ok, integer()} | :error
  defp static_color_constant("black"), do: {:ok, 0xC0}
  defp static_color_constant("white"), do: {:ok, 0xFF}
  defp static_color_constant("red"), do: {:ok, 0xE0}
  defp static_color_constant("green"), do: {:ok, 0xCC}
  defp static_color_constant("blue"), do: {:ok, 0xC3}
  defp static_color_constant("clear"), do: {:ok, 0x00}
  defp static_color_constant(_name), do: :error

  @spec hydrate_runtime_model_launch_context(Types.inner_runtime_model(), Types.app_model()) ::
          Types.inner_runtime_model()
  defp hydrate_runtime_model_launch_context(runtime_model, model)
       when is_map(runtime_model) and is_map(model) do
    runtime_model
    |> put_launch_context_value_if_missing(
      "screenW",
      get_in(model, ["launch_context", "screen", "width"])
    )
    |> put_launch_context_value_if_missing(
      "screenH",
      get_in(model, ["launch_context", "screen", "height"])
    )
    |> put_launch_context_value_if_missing(
      "displayShape",
      launch_context_display_shape_ctor(Map.get(model, "launch_context"))
    )
    |> put_launch_context_value_if_missing(
      "colorMode",
      launch_context_color_capability(Map.get(model, "launch_context"))
    )
  end

  @spec put_launch_context_value_if_missing(
          Types.app_model(),
          String.t(),
          Types.wire_scalar() | Types.launch_context()
        ) :: Types.app_model()
  defp put_launch_context_value_if_missing(runtime_model, key, value)
       when is_map(runtime_model) and is_binary(key) and not is_nil(value) do
    case Map.get(runtime_model, key) do
      nil ->
        Map.put(runtime_model, key, value)

      current when key in ["screenW", "screenH"] and is_integer(current) and current <= 0 ->
        Map.put(runtime_model, key, value)

      current when is_map(current) ->
        if unresolved_runtime_value?(current),
          do: Map.put(runtime_model, key, value),
          else: runtime_model

      _ ->
        runtime_model
    end
  end

  defp put_launch_context_value_if_missing(runtime_model, _key, _value)
       when is_map(runtime_model),
       do: runtime_model

  @spec unresolved_runtime_value?(Types.wire_input()) :: boolean()
  defp unresolved_runtime_value?(%{"$field" => field, "$on" => _}) when is_binary(field), do: true

  defp unresolved_runtime_value?(%{:"$field" => field, :"$on" => _}) when is_binary(field),
    do: true

  defp unresolved_runtime_value?(value), do: RuntimeModelQuality.unresolved_value?(value)

  @spec launch_context_display_shape(Types.launch_context()) :: String.t() | nil
  defp launch_context_display_shape(%{"screen" => %{} = screen}) do
    cond do
      Map.get(screen, "shape") in ["Round", "Rectangular"] ->
        Map.get(screen, "shape")

      Map.get(screen, "shape") == "round" ->
        "Round"

      Map.get(screen, "shape") == "rect" ->
        "Rectangular"

      Map.get(screen, "isRound") == true ->
        "Round"

      Map.get(screen, "isRound") == false ->
        "Rectangular"

      true ->
        nil
    end
  end

  defp launch_context_display_shape(%{"shape" => shape}) when shape in ["round", "rect"] do
    if shape == "round", do: "Round", else: "Rectangular"
  end

  defp launch_context_display_shape(_launch_context), do: nil

  @spec launch_context_display_shape_ctor(Types.launch_context()) ::
          Types.protocol_ctor_value() | nil
  defp launch_context_display_shape_ctor(launch_context) when is_map(launch_context) do
    case launch_context_display_shape(launch_context) do
      "Round" -> %{"ctor" => "Round", "args" => []}
      "Rectangular" -> %{"ctor" => "Rectangular", "args" => []}
      _ -> nil
    end
  end

  defp launch_context_display_shape_ctor(_launch_context), do: nil

  @spec launch_context_color_capability(Types.launch_context()) ::
          Types.protocol_ctor_value() | nil
  defp launch_context_color_capability(launch_context) when is_map(launch_context) do
    case RuntimeSurfaces.launch_context_color_mode(launch_context) do
      "BlackWhite" -> %{"ctor" => "BlackWhite", "args" => []}
      "Color" -> %{"ctor" => "Color", "args" => []}
      _ -> nil
    end
  end

  defp launch_context_color_capability(_launch_context), do: nil

  @spec message_constructor_value?(Types.protocol_ctor_value(), String.t()) :: boolean()
  defp message_constructor_value?(value, constructor)
       when is_map(value) and is_binary(constructor) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    ctor == constructor
  end

  defp message_constructor_value?(_value, _constructor), do: false
end
