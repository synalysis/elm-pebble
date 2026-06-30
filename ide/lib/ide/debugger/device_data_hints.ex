defmodule Ide.Debugger.DeviceDataHints do
  @moduledoc ""

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.RuntimeModelNormalize
  alias Ide.Debugger.RuntimeModelPreview
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type scalar_kind :: :string | :integer | :boolean

  @device_kind_runtime_fields %{
    "current_time_string" => ["timeString"],
    "current_date_time" => ["now", "currentDateTime"],
    "battery_level" => ["batteryLevel", "batteryPercent"],
    "connection_status" => ["connected", "online"],
    "timezone" => ["timezone"],
    "watch_model" => ["watchModel", "model"],
    "watch_color" => ["watchColor", "color"],
    "firmware_version" => ["firmwareVersion"]
  }

  @spec runtime_fields_by_device_kind() :: %{String.t() => [String.t()]}
  def runtime_fields_by_device_kind, do: @device_kind_runtime_fields

  @spec apply_to_state(Types.runtime_state(), Types.surface_target(), Types.device_request()) ::
          Types.runtime_state()
  def apply_to_state(state, target, req)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(req) do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)
    execution_model = Surface.execution_model(surface)
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    preview = Map.get(req, :preview)

    runtime_model =
      case {Map.get(req, :kind), preview} do
        {"current_time_string", %{"string" => hhmm_text} = preview} ->
          runtime_model
          |> RuntimeModelPreview.merge_matching_fields(preview)
          |> RuntimeModelPreview.merge_matching_fields(%{"string" => hhmm_text})
          |> merge_declared_scalar_device_response(execution_model, req, hhmm_text, :string)

        {"clock_style_24h", value} when is_boolean(value) ->
          put_boolean_device_response(runtime_model, execution_model, req, value)

        {"timezone_is_set", value} when is_boolean(value) ->
          put_boolean_device_response(runtime_model, execution_model, req, value)

        {"timezone", value} when is_binary(value) ->
          merge_declared_scalar_device_response(
            runtime_model,
            execution_model,
            req,
            value,
            :string
          )

        {"watch_model", value} when is_binary(value) ->
          merge_declared_scalar_device_response(
            runtime_model,
            execution_model,
            req,
            value,
            :string
          )

        {"watch_color", value} when is_binary(value) ->
          merge_declared_scalar_device_response(
            runtime_model,
            execution_model,
            req,
            value,
            :string
          )

        {"firmware_version", value} when is_binary(value) ->
          merge_declared_scalar_device_response(
            runtime_model,
            execution_model,
            req,
            value,
            :string
          )

        {"current_date_time", preview} when is_map(preview) ->
          put_declared_record_device_response(runtime_model, execution_model, "now", preview)

        {"battery_level", preview} when is_map(preview) ->
          level = Map.get(preview, "batteryLevel") || Map.get(preview, "percent")

          runtime_model =
            if is_integer(level) do
              merge_declared_scalar_device_response(
                runtime_model,
                execution_model,
                req,
                level,
                :integer
              )
            else
              runtime_model
            end

          RuntimeModelPreview.merge_matching_fields(runtime_model, preview)

        {"connection_status", preview} when is_map(preview) ->
          connected = Map.get(preview, "connected") || Map.get(preview, "online")

          runtime_model =
            if is_boolean(connected) do
              put_boolean_device_response(runtime_model, execution_model, req, connected)
            else
              runtime_model
            end

          RuntimeModelPreview.merge_matching_fields(runtime_model, preview)

        {_kind, value} when is_map(value) ->
          RuntimeModelPreview.merge_matching_fields(runtime_model, value)

        _ ->
          runtime_model
      end

    model =
      model
      |> Map.put("runtime_model", runtime_model)
      |> maybe_put_device_preview(req)

    view_tree = surface.view_tree || %{}

    refreshed_model =
      StepExecution.refresh_runtime_fingerprints(model, runtime_model, view_tree)

    surface
    |> Surface.put_app_model(refreshed_model)
    |> then(&Surface.put_in_state(state, target, &1))
  end

  def apply_to_state(state, _target, _req), do: state

  @spec merge_declared_scalar_device_response(
          Types.inner_runtime_model(),
          Types.execution_model(),
          Types.device_request(),
          String.t() | integer() | boolean(),
          scalar_kind()
        ) :: Types.inner_runtime_model()
  defp merge_declared_scalar_device_response(runtime_model, model, req, value, kind)
       when is_map(runtime_model) and is_map(model) and is_map(req) and
              kind in [:string, :integer, :boolean] do
    with true <- device_response_constructor_declared?(model, Map.get(req, :response_message)),
         {:ok, key} <-
           scalar_runtime_model_key_for_device_response(model, runtime_model, req, kind) do
      Map.put(runtime_model, key, value)
    else
      _ -> runtime_model
    end
  end

  defp merge_declared_scalar_device_response(runtime_model, _model, _req, _value, _kind),
    do: runtime_model

  @spec scalar_runtime_model_key_for_device_response(
          Types.execution_model(),
          Types.inner_runtime_model(),
          Types.device_request(),
          scalar_kind()
        ) :: {:ok, String.t()} | :error
  defp scalar_runtime_model_key_for_device_response(model, runtime_model, req, kind)
       when is_map(model) and is_map(runtime_model) and is_map(req) and
              kind in [:string, :integer, :boolean] do
    case unique_scalar_runtime_model_key(model, runtime_model, kind) do
      {:ok, key} ->
        {:ok, key}

      :error ->
        device_kind_runtime_model_key(model, runtime_model, Map.get(req, :kind), kind)
    end
  end

  @spec device_kind_runtime_model_key(
          Types.execution_model(),
          Types.inner_runtime_model(),
          String.t() | nil,
          scalar_kind()
        ) :: {:ok, String.t()} | :error
  defp device_kind_runtime_model_key(model, runtime_model, device_kind, kind)
       when is_map(model) and is_map(runtime_model) and kind in [:string, :integer, :boolean] do
    init_model = RuntimeModelNormalize.init_model(model)

    device_kind
    |> then(fn device_kind_key ->
      if is_binary(device_kind_key),
        do: Map.get(@device_kind_runtime_fields, device_kind_key, []),
        else: []
    end)
    |> Enum.filter(fn key ->
      Map.has_key?(runtime_model, key) and scalar_kind?(Map.get(init_model, key), kind)
    end)
    |> case do
      [key] -> {:ok, key}
      _ -> :error
    end
  end

  defp device_kind_runtime_model_key(_model, _runtime_model, _device_kind, _kind), do: :error

  @spec device_response_constructor_declared?(Types.execution_model(), String.t() | nil) ::
          boolean()
  defp device_response_constructor_declared?(model, constructor)
       when is_map(model) and is_binary(constructor) and constructor != "" do
    case RuntimeArtifacts.introspect(model) do
      ei when is_map(ei) ->
        ei
        |> Map.get("update_case_branches")
        |> case do
          branches when is_list(branches) ->
            Enum.any?(branches, fn branch ->
              is_binary(branch) and RuntimeModelMessages.wire_constructor(branch) == constructor
            end)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp device_response_constructor_declared?(_model, _constructor), do: false

  @spec unique_scalar_runtime_model_key(
          Types.execution_model(),
          Types.inner_runtime_model(),
          scalar_kind()
        ) :: {:ok, String.t()} | :error
  defp unique_scalar_runtime_model_key(model, runtime_model, kind)
       when is_map(model) and is_map(runtime_model) and kind in [:string, :integer, :boolean] do
    model
    |> RuntimeModelNormalize.init_model()
    |> Enum.filter(fn {key, value} ->
      scalar_kind?(value, kind) and Map.has_key?(runtime_model, key)
    end)
    |> case do
      [{key, _value}] -> {:ok, key}
      _ -> :error
    end
  end

  defp unique_scalar_runtime_model_key(_model, _runtime_model, _kind), do: :error

  defp scalar_kind?(value, kind) when kind in [:string, :integer, :boolean] do
    (kind == :string and is_binary(value)) or
      (kind == :integer and is_integer(value)) or
      (kind == :boolean and is_boolean(value))
  end

  @spec maybe_put_device_preview(Types.app_model(), Types.device_request()) :: Types.app_model()
  defp maybe_put_device_preview(model, req) when is_map(model) and is_map(req) do
    preview = Map.get(req, :preview)
    kind = Map.get(req, :kind)

    if not is_nil(preview) and is_binary(kind) do
      Map.put(model, "debugger_device_#{kind}", preview)
    else
      model
    end
  end

  defp maybe_put_device_preview(model, _req), do: model

  @spec put_boolean_device_response(
          Types.inner_runtime_model(),
          Types.execution_model(),
          Types.device_request(),
          boolean()
        ) :: Types.inner_runtime_model()
  defp put_boolean_device_response(runtime_model, model, req, value)
       when is_map(runtime_model) and is_map(model) and is_map(req) and is_boolean(value) do
    ctor = Map.get(req, :response_message)

    case boolean_fields_for_update_ctor(model, ctor) do
      [field] ->
        Map.put(runtime_model, field, value)

      _ ->
        merge_declared_scalar_device_response(runtime_model, model, req, value, :boolean)
    end
  end

  @spec boolean_fields_for_update_ctor(Types.execution_model(), String.t() | nil) :: [String.t()]
  defp boolean_fields_for_update_ctor(model, ctor)
       when is_map(model) and is_binary(ctor) and ctor != "" do
    init = RuntimeModelNormalize.init_model(model)

    case RuntimeArtifacts.introspect(model) do
      ei when is_map(ei) ->
        ei
        |> Map.get("update_ctor_model_fields", %{})
        |> Map.get(ctor, %{})
        |> declared_model_fields(init)

      _ ->
        []
    end
  end

  defp boolean_fields_for_update_ctor(_model, _ctor), do: []

  @spec declared_model_fields(Types.protocol_var_bindings(), Types.init_model_values()) ::
          [String.t()]
  defp declared_model_fields(bindings, init) when is_map(bindings) and is_map(init) do
    bindings
    |> Map.values()
    |> Enum.filter(fn field ->
      is_binary(field) and
        (Map.has_key?(init, field) or Map.has_key?(init, String.to_atom(field)))
    end)
  end

  defp declared_model_fields(_bindings, _init), do: []

  @spec put_declared_record_device_response(
          Types.inner_runtime_model(),
          Types.execution_model(),
          String.t(),
          Types.protocol_wire_arg()
        ) :: Types.inner_runtime_model()
  defp put_declared_record_device_response(runtime_model, model, field, value)
       when is_map(runtime_model) and is_map(model) and is_binary(field) do
    init = RuntimeModelNormalize.init_model(model)

    if Map.has_key?(init, field) do
      shape = Map.get(init, field)

      wrapped =
        case shape do
          %{"ctor" => "Just", "args" => _} -> %{"ctor" => "Just", "args" => [value]}
          %{"ctor" => "Nothing", "args" => _} -> %{"ctor" => "Just", "args" => [value]}
          %{ctor: "Just", args: _} -> %{"ctor" => "Just", "args" => [value]}
          %{ctor: "Nothing", args: _} -> %{"ctor" => "Just", "args" => [value]}
          %{"$ctor" => "Just", "$args" => _} -> %{"ctor" => "Just", "args" => [value]}
          %{"$ctor" => "Nothing", "$args" => _} -> %{"ctor" => "Just", "args" => [value]}
          _ -> value
        end

      Map.put(runtime_model, field, wrapped)
    else
      runtime_model
    end
  end

  defp put_declared_record_device_response(runtime_model, _model, _field, _value),
    do: runtime_model
end
