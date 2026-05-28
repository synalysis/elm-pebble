defmodule Ide.Debugger.ProtocolRuntimeMetadata do
  @moduledoc false

  alias Ide.Debugger.Types

  @protocol_metadata_keys [
    "protocol_inbound_count",
    "protocol_message_count",
    "protocol_last_inbound_message",
    "protocol_last_inbound_from"
  ]

  @spec preserve(Types.app_model(), Types.app_model()) :: Types.app_model()
  def preserve(model, previous_model) when is_map(model) and is_map(previous_model) do
    runtime_model = Map.get(model, "runtime_model")

    model =
      Enum.reduce(@protocol_metadata_keys, model, fn key, acc ->
        maybe_put(acc, key, value_from(previous_model, key))
      end)

    if is_map(runtime_model) do
      preserved =
        Enum.reduce(@protocol_metadata_keys, runtime_model, fn key, acc ->
          if Map.has_key?(runtime_model, key) or
               Map.has_key?(Map.get(previous_model, "runtime_model") || %{}, key) do
            maybe_put(acc, key, value_from(previous_model, key))
          else
            acc
          end
        end)

      Map.put(model, "runtime_model", preserved)
    else
      model
    end
  end

  def preserve(model, _previous_model), do: model

  @spec value_from(Types.app_model(), String.t()) :: Types.protocol_metadata_value()
  defp value_from(previous_model, key) when is_map(previous_model) and is_binary(key) do
    Map.get(previous_model, key) || get_in(previous_model, ["runtime_model", key])
  end

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value) when is_map(map), do: Map.put(map, key, value)
end
