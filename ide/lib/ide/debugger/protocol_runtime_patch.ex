defmodule Ide.Debugger.ProtocolRuntimePatch do
  @moduledoc false

  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.Types

  @spec patch_watch_runtime_from_protocol_message(
          Types.runtime_state(),
          Types.surface_target(),
          Types.protocol_ctor_value() | map(),
          Types.elm_introspect() | map() | nil
        ) ::
          Types.runtime_state()
  defp patch_watch_runtime_from_protocol_message(state, :watch, message_value, ei) do
    ei = if is_map(ei), do: ei, else: %{}

    patch =
      case subscription_payload_model_patch(ei, message_value) do
        patch when is_map(patch) and map_size(patch) > 0 -> patch
        _ -> protocol_runtime_model_patch_from_message_value(ei, message_value)
      end

    state =
      if map_size(patch) > 0 do
        update_in(state, [:watch, :model], fn model ->
          merge_protocol_runtime_model_patch(model, patch, ei)
        end)
      else
        state
      end

    case protocol_watch_online_from_message_value(message_value) do
      online when is_boolean(online) ->
        update_in(state, [:watch, :model, "runtime_model"], fn runtime_model ->
          runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
          Map.put(runtime_model, "online", online)
        end)

      _ ->
        state
    end
  end

  @spec merge_protocol_runtime_model_patch(map(), map(), map() | nil) :: map()
  defp merge_protocol_runtime_model_patch(model, patch, introspect) when is_map(model) do
    if is_map(patch) and patch != %{} and not noop_provide_position_patch?(patch) do
      patch =
        patch
        |> reject_protocol_result_wrapper_patch_values()
        |> promote_protocol_result_record_patch()
        |> align_protocol_patch_to_init_model(introspect)
        |> wrap_protocol_patch_fields_to_init_model(introspect)

      update_in(model, ["runtime_model"], fn runtime_model ->
        Map.merge(if(is_map(runtime_model), do: runtime_model, else: %{}), patch)
      end)
    else
      model
    end
  end

  @spec reject_protocol_result_wrapper_patch_values(map()) :: map()
  defp reject_protocol_result_wrapper_patch_values(patch) when is_map(patch) do
    patch
    |> Enum.reject(fn {_key, value} -> protocol_result_wrapper_patch_value?(value) end)
    |> Map.new()
  end

  @spec protocol_result_wrapper_patch_value?(Types.protocol_ctor_value() | map()) :: boolean()
  defp protocol_result_wrapper_patch_value?(%{"ctor" => ctor, "args" => _})
       when ctor in ["Ok", "Err"],
       do: true

  defp protocol_result_wrapper_patch_value?(_), do: false

  @spec noop_provide_position_patch?(map()) :: boolean()
  defp noop_provide_position_patch?(%{
         "latitudeE6" => 0,
         "longitudeE6" => 0,
         "accuracyM" => 0
       }),
       do: true

  defp noop_provide_position_patch?(_patch), do: false

  @spec align_protocol_patch_to_init_model(map(), map() | nil) :: map()
  defp align_protocol_patch_to_init_model(patch, introspect)
       when is_map(patch) and is_map(introspect) do
    init_keys =
      (Map.get(introspect, "init_model") || %{})
      |> Map.keys()
      |> Enum.map(&to_string/1)

    patch
    |> remap_geolocation_patch_keys()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = to_string(key)

      cond do
        key in init_keys ->
          Map.put(acc, key, value)

        true ->
          case model_field_for_patch_field(key, init_keys) do
            target when is_binary(target) -> Map.put(acc, target, value)
            _ -> acc
          end
      end
    end)
  end

  defp align_protocol_patch_to_init_model(patch, _introspect),
    do: remap_geolocation_patch_keys(patch)

  @spec remap_geolocation_patch_keys(map()) :: map()
  defp remap_geolocation_patch_keys(patch) when is_map(patch) do
    patch
    |> maybe_remap_patch_key("latitude", "latitudeE6", &latitude_to_microdegrees/1)
    |> maybe_remap_patch_key("longitude", "longitudeE6", &longitude_to_microdegrees/1)
    |> maybe_remap_patch_key("accuracy", "accuracyM", &Geolocation.round_number/1)
  end

  @spec maybe_remap_patch_key(map(), String.t(), String.t(), (Types.wire_input() ->
                                                                Types.wire_input())) :: map()
  defp maybe_remap_patch_key(patch, from, to, converter)
       when is_map(patch) and is_binary(from) and is_binary(to) do
    case Map.fetch(patch, from) do
      {:ok, value} -> patch |> Map.delete(from) |> Map.put(to, converter.(value))
      :error -> patch
    end
  end

  @spec latitude_to_microdegrees(number() | String.t()) :: integer()
  defp latitude_to_microdegrees(value) when is_integer(value) and value > 1_000_000, do: value

  defp latitude_to_microdegrees(value) when is_integer(value),
    do: round(value * 1_000_000)

  defp latitude_to_microdegrees(value) when is_float(value),
    do: round(value * 1_000_000)

  defp latitude_to_microdegrees(value), do: value

  @spec longitude_to_microdegrees(number() | String.t()) :: integer()
  defp longitude_to_microdegrees(value) when is_integer(value) and abs(value) > 1_000_000,
    do: value

  defp longitude_to_microdegrees(value) when is_integer(value),
    do: round(value * 1_000_000)

  defp longitude_to_microdegrees(value) when is_float(value),
    do: round(value * 1_000_000)

  defp longitude_to_microdegrees(value), do: value

  @spec model_field_for_patch_field(String.t(), [String.t()]) :: String.t() | nil
  defp model_field_for_patch_field(patch_key, init_keys)
       when is_binary(patch_key) and is_list(init_keys) do
    suffix =
      patch_key
      |> String.split("_")
      |> Enum.map_join("", &String.capitalize/1)

  if suffix == "" do
      nil
    else
      Enum.find(init_keys, fn model_key ->
        is_binary(model_key) and model_key != patch_key and String.ends_with?(model_key, suffix)
      end)
    end
  end

  defp model_field_for_patch_field(_patch_key, _init_keys), do: nil

  @spec protocol_runtime_model_patch_from_message_value(
          map() | nil,
          Types.protocol_ctor_value() | map()
        ) :: map()
  defp protocol_runtime_model_patch_from_message_value(introspect, %{
         "ctor" => "FromPhone",
         "args" => [inner | _]
       })
       when is_map(introspect) and is_map(inner) do
    protocol_runtime_model_patch_from_message_value(introspect, inner)
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{
         ctor: "FromPhone",
         args: [inner | _]
       })
       when is_map(introspect) and is_map(inner) do
    protocol_runtime_model_patch_from_message_value(introspect, %{
      "ctor" => "FromPhone",
      "args" => [inner]
    })
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{
         "ctor" => ctor,
         "args" => args
       })
       when is_map(introspect) and is_binary(ctor) and is_list(args) do
    with names when names != [] and length(names) == length(args) <-
           protocol_ctor_binding_names(introspect, ctor) do
      names
      |> Enum.zip(args)
      |> Map.new(fn {key, value} -> {key, wrap_protocol_patch_value(introspect, key, value)} end)
      |> promote_protocol_result_record_patch()
      |> apply_update_branch_field_aliases(introspect, ctor)
    else
      _ ->
        case protocol_provide_ctor_patch(introspect, %{"ctor" => ctor, "args" => args}) do
          patch when is_map(patch) and map_size(patch) > 0 ->
            patch

          _ ->
            protocol_runtime_model_patch_from_ok_payload(introspect, args)
        end
    end
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{ctor: ctor, args: args})
       when is_map(introspect) and is_binary(ctor) and is_list(args) do
    protocol_runtime_model_patch_from_message_value(introspect, %{"ctor" => ctor, "args" => args})
  end

  defp protocol_runtime_model_patch_from_message_value(introspect, %{
         "ctor" => callback,
         "args" => [inner | _]
       })
       when is_map(introspect) and is_binary(callback) and is_map(inner) do
    with %{"ctor" => ctor, "args" => args} <- inner,
         true <- is_binary(ctor) and is_list(args),
         names when length(names) == length(args) <-
           protocol_update_binding_names(introspect, callback, ctor) do
      names
      |> Enum.zip(args)
      |> Map.new()
    else
      _ -> %{}
    end
  end

  defp protocol_runtime_model_patch_from_message_value(_introspect, _message_value), do: %{}

  @spec protocol_provide_ctor_patch(map(), map()) :: map()
  defp protocol_provide_ctor_patch(introspect, %{"ctor" => "ProvidePosition", "args" => args})
       when is_map(introspect) and is_list(args) do
    case args do
      [lat, lon, acc | _] when is_number(lat) and is_number(lon) and is_number(acc) ->
        %{
          "latitudeE6" => Geolocation.position_microdegrees(lat),
          "longitudeE6" => Geolocation.position_microdegrees(lon),
          "accuracyM" => round(acc)
        }
        |> align_protocol_patch_to_init_model(introspect)

      _ ->
        %{}
    end
  end

  defp protocol_provide_ctor_patch(introspect, %{"ctor" => ctor, "args" => args})
       when is_map(introspect) and is_binary(ctor) and is_list(args) do
    if String.starts_with?(ctor, "Provide") do
      case provide_ctor_model_field(introspect, ctor) do
        field when is_binary(field) ->
          value =
            case args do
              [one] -> wrap_protocol_patch_value(introspect, field, one)
              _ -> wrap_protocol_patch_value(introspect, field, args)
            end

          %{field => value}
          |> mirror_related_runtime_model_fields(introspect)

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp protocol_provide_ctor_patch(_introspect, _message_value), do: %{}

  @spec mirror_related_runtime_model_fields(map(), map()) :: map()
  defp mirror_related_runtime_model_fields(patch, introspect)
       when is_map(patch) and is_map(introspect) do
    init = Map.get(introspect, "init_model") || %{}

    Enum.reduce(patch, patch, fn {source_key, value}, acc ->
      target =
        introspect
        |> Map.get("update_case_branches", [])
        |> Enum.find_value(fn branch ->
          if is_binary(branch) and String.contains?(branch, "Provide") do
            branch
            |> parse_update_branch_field_aliases()
            |> Map.get(source_key)
          end
        end)

      case {value, target, Map.has_key?(init, target)} do
        {val, field, true} when not is_nil(val) and is_binary(field) -> Map.put(acc, field, val)
        _ -> acc
      end
    end)
  end

  defp mirror_related_runtime_model_fields(patch, _introspect), do: patch

  @spec provide_ctor_model_field(map(), String.t()) :: String.t() | nil
  defp provide_ctor_model_field(introspect, ctor) when is_map(introspect) and is_binary(ctor) do
    case protocol_ctor_binding_names(introspect, ctor) do
      [field | _] when is_binary(field) -> field
      _ -> nil
    end
  end

  defp provide_ctor_model_field(_introspect, _ctor), do: nil

  @spec wrap_protocol_patch_value(map(), String.t(), Types.wire_input()) :: Types.wire_input()
  defp wrap_protocol_patch_value(introspect, field, value)
       when is_map(introspect) and is_binary(field) do
    case value do
      %{"ctor" => ctor, "args" => _} when ctor in ["Just", "Nothing", "Ok", "Err"] ->
        value

      %{ctor: ctor, args: _} when ctor in ["Just", "Nothing", "Ok", "Err"] ->
        %{"ctor" => to_string(ctor), "args" => Map.get(value, :args) || []}

      _ ->
        wrap_protocol_patch_value_for_init(introspect, field, value)
    end
  end

  defp wrap_protocol_patch_value(_introspect, _field, value), do: value

  @spec wrap_protocol_patch_value_for_init(map(), String.t(), Types.wire_input()) ::
          Types.wire_input()
  defp wrap_protocol_patch_value_for_init(introspect, field, value)
       when is_map(introspect) and is_binary(field) do
    init = Map.get(introspect, "init_model") || %{}

    case Map.get(init, field) do
      %{"ctor" => "Just"} -> %{"ctor" => "Just", "args" => [value]}
      %{ctor: "Just"} -> %{"ctor" => "Just", "args" => [value]}
      %{"$ctor" => "Just"} -> %{"ctor" => "Just", "args" => [value]}
      %{"$ctor" => "Nothing"} -> %{"ctor" => "Just", "args" => [value]}
      %{ctor: "Nothing"} -> %{"ctor" => "Just", "args" => [value]}
      _ -> value
    end
  end

  defp wrap_protocol_patch_value_for_init(_introspect, _field, value), do: value

  @spec wrap_protocol_patch_fields_to_init_model(map(), map() | nil) :: map()
  defp wrap_protocol_patch_fields_to_init_model(patch, introspect)
       when is_map(patch) and is_map(introspect) do
    Map.new(patch, fn {key, value} ->
      {key, wrap_protocol_patch_value(introspect, key, value)}
    end)
  end

  defp wrap_protocol_patch_fields_to_init_model(patch, _introspect), do: patch

  @spec subscription_payload_model_patch(map() | nil, Types.subscription_payload()) :: map()
  defp subscription_payload_model_patch(introspect, %{"ctor" => _ctor, "args" => args})
       when is_map(introspect) and is_list(args) do
    protocol_runtime_model_patch_from_ok_payload(introspect, args)
  end

  defp subscription_payload_model_patch(introspect, %{ctor: _ctor, args: args})
       when is_map(introspect) and is_list(args) do
    subscription_payload_model_patch(introspect, %{"ctor" => "Msg", "args" => args})
  end

  defp subscription_payload_model_patch(_introspect, _message_value), do: %{}

  @spec protocol_runtime_model_patch_from_ok_payload(map(), list()) :: map()
  defp protocol_runtime_model_patch_from_ok_payload(introspect, [
         %{"ctor" => "Ok", "args" => [record | _]} | _
       ])
       when is_map(introspect) and is_map(record) do
    record
    |> promote_protocol_result_record_patch()
    |> align_protocol_patch_to_init_model(introspect)
  end

  defp protocol_runtime_model_patch_from_ok_payload(introspect, [
         %{ctor: "Ok", args: [record | _]} | _
       ])
       when is_map(introspect) and is_map(record) do
    protocol_runtime_model_patch_from_ok_payload(introspect, [
      %{"ctor" => "Ok", "args" => [record]}
    ])
  end

  defp protocol_runtime_model_patch_from_ok_payload(_introspect, _args), do: %{}

  @spec apply_update_branch_field_aliases(map(), map(), String.t()) :: map()
  defp apply_update_branch_field_aliases(patch, introspect, ctor)
       when is_map(patch) and is_map(introspect) and is_binary(ctor) do
    aliases = update_branch_field_aliases(introspect, ctor)

    Map.new(patch, fn {key, value} ->
      {Map.get(aliases, key, key), value}
    end)
  end

  defp apply_update_branch_field_aliases(patch, _introspect, _ctor), do: patch

  @spec update_branch_field_aliases(map(), String.t()) :: %{String.t() => String.t()}
  defp update_branch_field_aliases(introspect, ctor)
       when is_map(introspect) and is_binary(ctor) do
    introspect
    |> Map.get("update_case_branches", [])
    |> Enum.find_value(fn branch ->
      if is_binary(branch) and String.contains?(branch, ctor <> " ") do
        parse_update_branch_field_aliases(branch)
      end
    end)
    |> case do
      aliases when is_map(aliases) -> aliases
      _ -> %{}
    end
  end

  @spec parse_update_branch_field_aliases(String.t()) :: %{String.t() => String.t()}
  defp parse_update_branch_field_aliases(branch) when is_binary(branch) do
    ~r/([a-z][A-Za-z0-9_]*)\s*=\s*([a-z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)/u
    |> Regex.scan(branch)
    |> Map.new(fn [_full, target, _binding, source] -> {source, target} end)
  end

  @spec promote_protocol_result_record_patch(map()) :: map()
  defp promote_protocol_result_record_patch(patch) when is_map(patch) do
    case patch do
      %{"info" => wrapper} ->
        promote_protocol_result_wrapper(wrapper, Map.delete(patch, "info"))

      %{"value" => wrapper} ->
        promote_protocol_result_wrapper(wrapper, Map.delete(patch, "value"))

      patch ->
        Enum.reduce(patch, patch, fn {key, value}, acc ->
          case promote_protocol_result_wrapper(value, %{}) do
            extra when map_size(extra) > 0 -> Map.merge(Map.delete(acc, key), extra)
            _ -> acc
          end
        end)
    end
  end

  @spec promote_protocol_result_wrapper(Types.protocol_ctor_value() | map(), map()) :: map()
  defp promote_protocol_result_wrapper(%{"ctor" => ctor, "args" => [record | _]}, extra)
       when ctor in ["Ok", "Err"] and is_map(record) do
    cond do
      maybe_runtime_ctor?(record) -> extra
      elm_message_constructor_map?(record) -> extra
      true -> Map.merge(extra, record)
    end
  end

  defp promote_protocol_result_wrapper(%{ctor: ctor, args: [record | _]}, extra)
       when ctor in ["Ok", "Err"] and is_map(record) do
    promote_protocol_result_wrapper(%{"ctor" => ctor, "args" => [record]}, extra)
  end

  defp promote_protocol_result_wrapper(_wrapper, extra), do: extra

  @spec protocol_ctor_binding_names(map(), String.t()) :: [String.t()]
  defp protocol_ctor_binding_names(introspect, ctor)
       when is_map(introspect) and is_binary(ctor) do
    introspect
    |> Map.get("update_case_branches", [])
    |> Enum.find_value(fn branch ->
      if is_binary(branch) and String.contains?(branch, ctor) do
        parse_update_branch_binding_names(branch, ctor)
      end
    end)
    |> case do
      names when is_list(names) -> names
      _ -> []
    end
  end

  @spec protocol_update_binding_names(map(), String.t(), String.t()) :: [String.t()]
  defp protocol_update_binding_names(introspect, callback, ctor)
       when is_map(introspect) and is_binary(callback) and is_binary(ctor) do
    prefix = callback <> " " <> ctor

    introspect
    |> Map.get("update_case_branches", [])
    |> Enum.find(fn branch ->
      is_binary(branch) and String.starts_with?(String.trim(branch), prefix)
    end)
    |> case do
      branch when is_binary(branch) -> parse_update_branch_binding_names(branch, ctor)
      _ -> []
    end
  end

  @spec parse_update_branch_binding_names(String.t(), String.t()) :: [String.t()]
  defp parse_update_branch_binding_names(branch, ctor)
       when is_binary(branch) and is_binary(ctor) do
    trimmed = String.trim(branch)

    cond do
      String.starts_with?(trimmed, ctor <> " ") ->
        trimmed
        |> String.replace_prefix(ctor, "")
        |> String.trim()
        |> String.split(~r/\s+/, trim: true)
        |> Enum.reject(&(&1 in ["Ok", "Err", "Nothing", "Just", "_"] or &1 == ctor))

      true ->
        inner =
          case Regex.run(~r/#{Regex.escape(ctor)}\s*\(([^)]*)\)/u, trimmed) do
            [_, captured] -> captured
            _ -> trimmed |> String.replace_prefix(ctor, "") |> String.trim()
          end

        ~r/[A-Za-z][A-Za-z0-9_]*/
        |> Regex.scan(inner)
        |> List.flatten()
        |> Enum.reject(&(&1 in ["Ok", "Err", "Nothing", "Just", "_"] or &1 == ctor))
    end
  end

  @spec protocol_watch_online_from_message_value(Types.protocol_ctor_value() | map()) ::
          boolean() | nil
  defp protocol_watch_online_from_message_value(%{"ctor" => "FromPhone", "args" => [inner | _]})
       when is_map(inner),
       do: protocol_watch_online_from_message_value(inner)

  defp protocol_watch_online_from_message_value(%{
         "ctor" => "ProvideConnectivity",
         "args" => [online | _]
       })
       when is_boolean(online),
       do: online

  defp protocol_watch_online_from_message_value(%{ctor: "FromPhone", args: [inner | _]})
       when is_map(inner),
       do: protocol_watch_online_from_message_value(inner)

  defp protocol_watch_online_from_message_value(%{
         ctor: "ProvideConnectivity",
         args: [online | _]
       })
       when is_boolean(online),
       do: online

  defp protocol_watch_online_from_message_value(_message_value), do: nil

  defp maybe_runtime_ctor?(%{"ctor" => ctor, "args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args), do: true

  defp maybe_runtime_ctor?(%{"$ctor" => ctor, "$args" => args})
       when ctor in ["Nothing", "Just"] and is_list(args), do: true

  defp maybe_runtime_ctor?(_value), do: false

  defp elm_message_constructor_map?(map) when is_map(map) do
    keys = map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    keys == ["args", "ctor"] or keys == ["$args", "$ctor"]
  end

  def runtime_patch_for_message(introspect, message_value) do
    subscription_payload_model_patch(introspect, message_value)
    |> Map.merge(patch_from_message_value(introspect, message_value))
  end

  def patch_from_message_value(introspect, message_value),
    do: protocol_runtime_model_patch_from_message_value(introspect, message_value)

  def merge_model_patch(model, patch, introspect),
    do: merge_protocol_runtime_model_patch(model, patch, introspect)

  def patch_watch(state, :watch, message_value, introspect) when is_map(state) do
    patch_watch_runtime_from_protocol_message(state, :watch, message_value, introspect)
  end

  def patch_watch(state, _recipient, _message_value, _introspect), do: state

  def watch_online_from_message(message_value),
    do: protocol_watch_online_from_message_value(message_value)
end
