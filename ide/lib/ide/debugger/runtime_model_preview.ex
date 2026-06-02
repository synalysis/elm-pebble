defmodule Ide.Debugger.RuntimeModelPreview do
  @moduledoc false

  alias Ide.Debugger.Types

  @type preview :: %{optional(String.t()) => Types.protocol_wire_arg()}
  @type model_key :: String.t() | atom()

  @spec merge_matching_fields(Types.inner_runtime_model(), preview()) ::
          Types.inner_runtime_model()
  def merge_matching_fields(runtime_model, preview)
      when is_map(runtime_model) and is_map(preview) do
    Enum.reduce(preview, runtime_model, fn {key, value}, acc ->
      key_text = to_string(key)

      case matching_model_key(acc, key_text) do
        nil ->
          acc

        model_key ->
          existing = Map.get(acc, model_key)

          case coerce_preview_value(existing, value) do
            {:ok, coerced} -> Map.put(acc, model_key, coerced)
            :error -> acc
          end
      end
    end)
  end

  def merge_matching_fields(runtime_model, _preview) when is_map(runtime_model), do: runtime_model

  @spec matching_model_key(Types.inner_runtime_model(), String.t()) :: model_key() | nil
  defp matching_model_key(model, key_text) when is_map(model) and is_binary(key_text) do
    Enum.find_value(model, fn {existing_key, _existing_value} ->
      if to_string(existing_key) == key_text, do: existing_key, else: nil
    end)
  end

  @spec coerce_preview_value(Types.protocol_wire_arg(), Types.protocol_wire_arg()) ::
          {:ok, Types.protocol_wire_arg()} | :error
  defp coerce_preview_value(existing, value) when is_integer(existing) and is_integer(value),
    do: {:ok, value}

  defp coerce_preview_value(existing, value) when is_boolean(existing) and is_boolean(value),
    do: {:ok, value}

  defp coerce_preview_value(existing, value) when is_binary(existing) and is_binary(value),
    do: {:ok, value}

  defp coerce_preview_value(existing, value) when is_float(existing) and is_number(value),
    do: {:ok, value * 1.0}

  defp coerce_preview_value(nil, value), do: {:ok, %{"ctor" => "Just", "args" => [value]}}

  defp coerce_preview_value(%{"$ctor" => ctor, "$args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: {:ok, %{"$ctor" => "Just", "$args" => [value]}}

  defp coerce_preview_value(%{"$ctor" => _ctor, "$args" => args}, value)
       when is_list(args) and is_binary(value),
       do: {:ok, %{"$ctor" => value, "$args" => []}}

  defp coerce_preview_value(%{"ctor" => ctor, "args" => args}, value)
       when ctor in ["Nothing", "Just"] and is_list(args),
       do: {:ok, %{"ctor" => "Just", "args" => [value]}}

  defp coerce_preview_value(%{"ctor" => _ctor, "args" => args}, value)
       when is_list(args) and is_binary(value),
       do: {:ok, %{"ctor" => value, "args" => []}}

  defp coerce_preview_value(_existing, _value), do: :error
end
