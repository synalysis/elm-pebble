defmodule Ide.Debugger.CompiledElixirCorpusHelpers do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.CompanionBridge.SimulatorStore
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings

  @spec corpus_enabled?() :: boolean()
  def corpus_enabled? do
    System.get_env("ELMX_TEMPLATE_CORPUS") in ["1", "true", "TRUE"]
  end

  @spec ensure_compiled_elixir_backend!() :: :ok
  def ensure_compiled_elixir_backend! do
    Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, execution_backend: :compiled_elixir)
    _ = Application.ensure_all_started(:elmx)
    :ok
  end

  @spec corpus_compile_smoke_failure?(term()) :: boolean()
  def corpus_compile_smoke_failure?(reason) do
    reason in [:unsupported_op, :emit_failed] or match?({:unsupported_op, _, _}, reason) or
      match?({:emit_failed, _}, reason)
  end

  @spec corpus_launch_context() :: map()
  def corpus_launch_context do
    corpus_launch_context_for("basalt")
  end

  @spec corpus_launch_context_for(String.t()) :: map()
  def corpus_launch_context_for(watch_profile_id) when is_binary(watch_profile_id) do
    Ide.Debugger.RuntimeSurfaces.launch_context_for(watch_profile_id, "LaunchUser")
  end

  @doc """
  Builds a protocol `FromPhone` wire `message_value` for companion watch steps.
  """
  @spec companion_from_phone_value(String.t(), list()) :: map()
  def companion_from_phone_value(inner_ctor, args) when is_binary(inner_ctor) and is_list(args) do
    companion_from_phone_inner(inner_ctor, args)
  end

  @doc """
  Wire `message_value` for watch `FromPhone` with a nullary `PhoneToWatch` constructor.
  """
  @spec companion_from_phone_nullary(String.t()) :: map()
  def companion_from_phone_nullary(inner_ctor) when is_binary(inner_ctor) do
    companion_from_phone_inner(inner_ctor, [])
  end

  defp companion_from_phone_inner(inner_ctor, args)
       when is_binary(inner_ctor) and is_list(args) do
    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => inner_ctor,
          "args" => Enum.map(args, &companion_wire_arg/1)
        }
      ]
    }
  end

  defp companion_wire_arg(value) when is_binary(value), do: value
  defp companion_wire_arg(value) when is_integer(value), do: value
  defp companion_wire_arg(value) when is_boolean(value), do: value

  defp companion_wire_arg(ctor) when is_atom(ctor),
    do: %{"ctor" => Atom.to_string(ctor), "args" => []}

  defp companion_wire_arg(%{"ctor" => _, "args" => _} = map), do: map

  @doc """
  Wire `Just` wrapper for optional companion bridge record fields.
  """
  @spec companion_wire_just(term()) :: map()
  def companion_wire_just(value), do: %{"ctor" => "Just", "args" => [value]}

  @doc """
  Wire `Nothing` for optional companion bridge record fields.
  """
  @spec companion_wire_nothing() :: map()
  def companion_wire_nothing(), do: %{"ctor" => "Nothing", "args" => []}

  @doc """
  Wire Elm unit `()` for `Result` Ok payloads (e.g. `PinInserted (Ok ())`).
  """
  @spec companion_wire_unit() :: map()
  def companion_wire_unit(), do: %{"ctor" => "()", "args" => []}

  @doc """
  Wire `message_value` for phone `GotToken (Ok token)`.
  """
  @spec companion_got_token_ok_value(String.t()) :: map()
  def companion_got_token_ok_value(token) when is_binary(token) do
    %{
      "ctor" => "GotToken",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [token]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `PinInserted (Ok ())`.
  """
  @spec companion_pin_inserted_ok_value() :: map()
  def companion_pin_inserted_ok_value do
    %{
      "ctor" => "PinInserted",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [companion_wire_unit()]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `GotBattery (Ok {percent, charging})` subscription followups.
  """
  @spec companion_got_battery_ok_value(integer(), boolean()) :: map()
  def companion_got_battery_ok_value(percent, charging)
      when is_integer(percent) and is_boolean(charging) do
    %{
      "ctor" => "GotBattery",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [%{"percent" => percent, "charging" => charging}]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `GotLocale (Ok {locale})`.
  """
  @spec companion_got_locale_ok_value(String.t()) :: map()
  def companion_got_locale_ok_value(locale) when is_binary(locale) do
    %{
      "ctor" => "GotLocale",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [%{"locale" => locale}]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `GotConnectivity Online|Offline` (no Result wrapper).
  """
  @spec companion_got_connectivity_value(atom() | String.t()) :: map()
  def companion_got_connectivity_value(ctor) when is_atom(ctor) do
    companion_got_connectivity_value(Atom.to_string(ctor))
  end

  def companion_got_connectivity_value(ctor) when is_binary(ctor) do
    %{
      "ctor" => "GotConnectivity",
      "args" => [%{"ctor" => ctor, "args" => []}]
    }
  end

  @doc """
  Wire `message_value` for phone `GotNotifications (Ok {notificationsEnabled, quietHours})`.
  """
  @spec companion_got_notifications_ok_value(boolean(), boolean()) :: map()
  def companion_got_notifications_ok_value(enabled, quiet_hours)
      when is_boolean(enabled) and is_boolean(quiet_hours) do
    %{
      "ctor" => "GotNotifications",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [
            %{"notificationsEnabled" => enabled, "quietHours" => quiet_hours}
          ]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `GotCalendar (Ok events)`.
  """
  @spec companion_got_calendar_ok_events(list(map())) :: map()
  def companion_got_calendar_ok_events(events) when is_list(events) do
    %{
      "ctor" => "GotCalendar",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [events]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `GotStorage (Ok (Storage.StringValue text))`.
  """
  @spec companion_got_storage_string_ok_value(String.t()) :: map()
  def companion_got_storage_string_ok_value(text) when is_binary(text) do
    %{
      "ctor" => "GotStorage",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [
            %{"ctor" => "StringValue", "args" => [text]}
          ]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `GotPreference (Ok (key, value))` subscription followups.

  Uses an Erlang pair tuple in `Ok` args (matches `CompanionBridge.subscription_result_message_value/3`).
  """
  @spec companion_got_preference_ok_value(String.t(), String.t()) :: map()
  def companion_got_preference_ok_value(key, pref_value)
      when is_binary(key) and is_binary(pref_value) do
    %{
      "ctor" => "GotPreference",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [{key, pref_value}]
        }
      ]
    }
  end

  @doc """
  Weather info map for `Weather.Current` bridge payloads.
  """
  @spec companion_weather_info(keyword()) :: map()
  def companion_weather_info(opts \\ []) when is_list(opts) do
    condition = Keyword.get(opts, :condition, "Clear")

    %{
      "temperatureC" => Keyword.get(opts, :temperature_c, 18),
      "condition" => %{"ctor" => to_string(condition), "args" => []},
      "humidityPercent" => Keyword.get(opts, :humidity_percent, 50),
      "pressureHpa" => Keyword.get(opts, :pressure_hpa, 1013),
      "windKph" => Keyword.get(opts, :wind_kph, 8)
    }
  end

  @doc """
  Wire `message_value` for phone `GotWeather (Ok (Weather.Current info))`.
  """
  @spec companion_got_weather_current_ok_value(map()) :: map()
  def companion_got_weather_current_ok_value(info) when is_map(info) do
    %{
      "ctor" => "GotWeather",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [
            %{"ctor" => "Current", "args" => [info]}
          ]
        }
      ]
    }
  end

  @doc """
  Environment info map for `Environment.current` bridge payloads.
  """
  @spec companion_environment_info(keyword()) :: map()
  def companion_environment_info(opts \\ []) when is_list(opts) do
    %{
      "sun" =>
        companion_wire_just(%{
          "sunriseMin" => Keyword.get(opts, :sunrise_min, 420),
          "sunsetMin" => Keyword.get(opts, :sunset_min, 1200),
          "polarDay" => Keyword.get(opts, :polar_day, false)
        }),
      "moon" =>
        companion_wire_just(%{
          "moonriseMin" => companion_wire_nothing(),
          "moonsetMin" => companion_wire_nothing(),
          "phaseE6" => Keyword.get(opts, :phase_e6, 500_000)
        })
    }
  end

  @doc """
  Geolocation location map for `Geolocation.currentPosition` bridge payloads.
  """
  @spec companion_location_info(keyword()) :: map()
  def companion_location_info(opts \\ []) when is_list(opts) do
    %{
      "latitude" => Keyword.get(opts, :latitude, 12.345),
      "longitude" => Keyword.get(opts, :longitude, -98.765),
      "accuracy" => Keyword.get(opts, :accuracy, 25.0)
    }
  end

  @doc """
  Wire `message_value` for phone `GotPosition (Ok location)`.
  """
  @spec companion_got_position_ok_value(map()) :: map()
  def companion_got_position_ok_value(location) when is_map(location) do
    %{
      "ctor" => "GotPosition",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [location]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `Connected (Ok ())`.
  """
  @spec companion_connected_ok_value() :: map()
  def companion_connected_ok_value do
    %{
      "ctor" => "Connected",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [companion_wire_unit()]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `WebSocketCommand (Ok ())`.
  """
  @spec companion_websocket_command_ok_value() :: map()
  def companion_websocket_command_ok_value do
    %{
      "ctor" => "WebSocketCommand",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [companion_wire_unit()]
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `WebSocketEvent event`.
  """
  @spec companion_websocket_event_value(String.t(), keyword()) :: map()
  def companion_websocket_event_value(event_ctor, opts \\ [])
      when is_binary(event_ctor) and is_list(opts) do
    event_args =
      case event_ctor do
        "Closed" -> [Keyword.get(opts, :code, companion_wire_nothing())]
        "Message" -> [Keyword.get(opts, :text, "ping")]
        "Error" -> [Keyword.get(opts, :error, "error")]
        _ -> []
      end

    %{
      "ctor" => "WebSocketEvent",
      "args" => [
        %{
          "ctor" => event_ctor,
          "args" => event_args
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `LifecycleChanged event`.
  """
  @spec companion_lifecycle_changed_value(String.t(), keyword()) :: map()
  def companion_lifecycle_changed_value(event_ctor, opts \\ [])
      when is_binary(event_ctor) and is_list(opts) do
    event_args =
      case event_ctor do
        "WebViewClosed" ->
          [Keyword.get(opts, :response, companion_wire_nothing())]

        "VisibilityChanged" ->
          [Keyword.get(opts, :visible, true)]

        _ ->
          []
      end

    %{
      "ctor" => "LifecycleChanged",
      "args" => [
        %{
          "ctor" => event_ctor,
          "args" => event_args
        }
      ]
    }
  end

  @doc """
  Wire `message_value` for phone `ConfigurationClosed maybeResponse`.
  """
  @spec companion_configuration_closed_value(String.t() | nil) :: map()
  def companion_configuration_closed_value(nil) do
    %{
      "ctor" => "ConfigurationClosed",
      "args" => [companion_wire_nothing()]
    }
  end

  def companion_configuration_closed_value(response) when is_binary(response) do
    %{
      "ctor" => "ConfigurationClosed",
      "args" => [companion_wire_just(response)]
    }
  end

  @doc """
  Wire `message_value` for phone `GotEnvironment (Ok info)`.
  """
  @spec companion_got_environment_ok_value(map()) :: map()
  def companion_got_environment_ok_value(info) when is_map(info) do
    %{
      "ctor" => "GotEnvironment",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [info]
        }
      ]
    }
  end

  @doc """
  Builds a single calendar event map for companion bridge payloads.
  """
  @spec companion_calendar_event(keyword()) :: map()
  def companion_calendar_event(opts) when is_list(opts) do
    %{
      "id" => Keyword.get(opts, :id, "event-1"),
      "title" => Keyword.get(opts, :title, "Event"),
      "startMillis" => Keyword.get(opts, :start_millis, 0),
      "endMillis" => Keyword.get(opts, :end_millis, 3_600_000),
      "allDay" => Keyword.get(opts, :all_day, false)
    }
  end

  @spec frame_tick_message(keyword()) :: String.t()
  def frame_tick_message(opts \\ []) do
    frame = Keyword.get(opts, :frame, 1)
    dt_ms = Keyword.get(opts, :dt_ms, 33)

    payload = %{
      "dtMs" => dt_ms,
      "elapsedMs" => frame * dt_ms,
      "frame" => frame
    }

    "FrameTick " <> Jason.encode!(payload)
  end

  @spec corpus_phone_init_execute!(String.t(), keyword()) ::
          {:ok, map(), map()} | {:compile_error, term()}
  def corpus_phone_init_execute!(phone_workspace, opts \\ []) when is_binary(phone_workspace) do
    revision =
      Keyword.get(
        opts,
        :revision,
        "corpus-phone-" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    strip? = Keyword.get(opts, :strip_dead_code, true)
    entry_module = Keyword.get(opts, :entry_module, "CompanionApp")
    rel_path = Keyword.get(opts, :rel_path, "src/#{entry_module}.elm")

    case Ide.Compiler.build_elmx_artifacts_in_memory(phone_workspace,
           revision: revision,
           strip_dead_code: strip?,
           entry_module: entry_module
         ) do
      {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} ->
        init_request = %{
          elmx_manifest: manifest,
          elmx_revision: revision,
          current_model: %{},
          message: nil,
          introspect: %{},
          source: "",
          source_root: "phone",
          rel_path: rel_path,
          current_view_tree: %{}
        }

        case Ide.Debugger.RuntimeExecutor.execute(init_request) do
          {:ok, payload} ->
            runtime_model = get_in(payload.model_patch, ["runtime_model"]) || %{}

            runtime_model =
              if Keyword.get(opts, :apply_companion_bridge_followups, false) do
                corpus_apply_companion_bridge_init_followups(
                  init_request,
                  runtime_model,
                  payload,
                  opts
                )
              else
                runtime_model
              end

            {:ok, manifest, runtime_model}

          {:error, reason} ->
            {:compile_error, reason}
        end

      {:error, reason} ->
        {:compile_error, reason}
    end
  end

  @spec corpus_phone_step_execute!(String.t(), String.t(), keyword()) ::
          {:ok, map(), map()} | {:compile_error, term()}
  def corpus_phone_step_execute!(phone_workspace, message, opts \\ [])
      when is_binary(phone_workspace) and is_binary(message) do
    revision =
      Keyword.get(
        opts,
        :revision,
        "corpus-phone-step-" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    strip? = Keyword.get(opts, :strip_dead_code, true)
    entry_module = Keyword.get(opts, :entry_module, "CompanionApp")
    rel_path = Keyword.get(opts, :rel_path, "src/#{entry_module}.elm")

    case Ide.Compiler.build_elmx_artifacts_in_memory(phone_workspace,
           revision: revision,
           strip_dead_code: strip?,
           entry_module: entry_module
         ) do
      {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} ->
        base_request = %{
          elmx_manifest: manifest,
          elmx_revision: revision,
          introspect: %{},
          source: "",
          source_root: "phone",
          rel_path: rel_path,
          current_view_tree: %{}
        }

        init_request = Map.put(base_request, :current_model, %{}) |> Map.put(:message, nil)

        with {:ok, init_payload} <- Ide.Debugger.RuntimeExecutor.execute(init_request) do
          runtime_model =
            case Keyword.get(opts, :current_runtime_model) do
              %{} = model -> model
              _ -> get_in(init_payload.model_patch, ["runtime_model"]) || %{}
            end

          step_request =
            base_request
            |> Map.put(:current_model, %{"runtime_model" => runtime_model})
            |> Map.put(:message, message)
            |> maybe_put_message_value(Keyword.get(opts, :message_value))

          case Ide.Debugger.RuntimeExecutor.execute(step_request) do
            {:ok, step_payload} ->
              {:ok, manifest, get_in(step_payload.model_patch, ["runtime_model"]) || %{}}

            {:error, reason} ->
              {:compile_error, reason}
          end
        else
          {:error, reason} -> {:compile_error, reason}
          _ -> {:compile_error, :init_failed}
        end

      {:error, reason} ->
        {:compile_error, reason}
    end
  end

  @spec corpus_compile_and_execute_init!(String.t(), keyword()) ::
          {:ok, map(), map()} | {:compile_error, term()}
  def corpus_compile_and_execute_init!(workspace, opts \\ []) when is_binary(workspace) do
    revision =
      Keyword.get(
        opts,
        :revision,
        "corpus-" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    strip? = Keyword.get(opts, :strip_dead_code, true)
    watch_profile_id = Keyword.get(opts, :watch_profile_id, "basalt")

    case Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
           revision: revision,
           strip_dead_code: strip?
         ) do
      {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} ->
        launch_context = corpus_launch_context_for(watch_profile_id)

        case Ide.Debugger.RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{"launch_context" => launch_context},
               message: nil,
               introspect: %{},
               source: "",
               source_root: "watch",
               rel_path: "src/Main.elm",
               current_view_tree: %{}
             }) do
          {:ok, payload} ->
            {:ok, manifest, get_in(payload.model_patch, ["runtime_model"]) || %{}}

          {:error, reason} ->
            {:compile_error, reason}
        end

      {:error, reason} ->
        {:compile_error, reason}
    end
  end

  @spec corpus_compile_and_execute_step!(String.t(), String.t(), keyword()) ::
          {:ok, map(), map()} | {:compile_error, term()}
  def corpus_compile_and_execute_step!(workspace, message, opts \\ [])
      when is_binary(workspace) and is_binary(message) do
    revision =
      Keyword.get(
        opts,
        :revision,
        "corpus-step-" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    strip? = Keyword.get(opts, :strip_dead_code, true)
    watch_profile_id = Keyword.get(opts, :watch_profile_id, "basalt")

    case Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
           revision: revision,
           strip_dead_code: strip?
         ) do
      {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} ->
        launch_context = corpus_launch_context_for(watch_profile_id)

        init_request = %{
          elmx_manifest: manifest,
          elmx_revision: revision,
          current_model: %{"launch_context" => launch_context},
          message: nil,
          introspect: %{},
          source: "",
          source_root: "watch",
          rel_path: "src/Main.elm",
          current_view_tree: %{}
        }

        with {:ok, init_payload} <- Ide.Debugger.RuntimeExecutor.execute(init_request),
             runtime_model <- get_in(init_payload.model_patch, ["runtime_model"]) || %{} do
          step_request =
            init_request
            |> Map.merge(%{
              current_model: %{
                "launch_context" => launch_context,
                "runtime_model" => runtime_model
              },
              message: message
            })
            |> maybe_put_message_value(Keyword.get(opts, :message_value))

          case Ide.Debugger.RuntimeExecutor.execute(step_request) do
            {:ok, step_payload} ->
              {:ok, manifest, get_in(step_payload.model_patch, ["runtime_model"]) || %{}}

            {:error, reason} ->
              {:compile_error, reason}
          end
        else
          {:error, reason} -> {:compile_error, reason}
          _ -> {:compile_error, :init_failed}
        end

      {:error, reason} ->
        {:compile_error, reason}
    end
  end

  @spec corpus_compile_and_execute_steps!(String.t(), [String.t()], keyword()) ::
          {:ok, map(), map()} | {:compile_error, term()}
  def corpus_compile_and_execute_steps!(workspace, messages, opts \\ [])
      when is_binary(workspace) and is_list(messages) do
    revision =
      Keyword.get(
        opts,
        :revision,
        "corpus-steps-" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    strip? = Keyword.get(opts, :strip_dead_code, true)
    watch_profile_id = Keyword.get(opts, :watch_profile_id, "basalt")

    case Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
           revision: revision,
           strip_dead_code: strip?
         ) do
      {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} ->
        launch_context = corpus_launch_context_for(watch_profile_id)

        base_request = %{
          elmx_manifest: manifest,
          elmx_revision: revision,
          introspect: %{},
          source: "",
          source_root: "watch",
          rel_path: "src/Main.elm",
          current_view_tree: %{}
        }

        init_request =
          Map.put(base_request, :current_model, %{"launch_context" => launch_context})
          |> Map.put(:message, nil)

        with {:ok, init_payload} <- Ide.Debugger.RuntimeExecutor.execute(init_request),
             runtime_model <- get_in(init_payload.model_patch, ["runtime_model"]) || %{} do
          messages
          |> Enum.reduce_while({:ok, runtime_model}, fn message, {:ok, model} ->
            step_request =
              base_request
              |> Map.put(:current_model, %{
                "launch_context" => launch_context,
                "runtime_model" => model
              })
              |> Map.put(:message, message)
              |> maybe_put_message_value(Keyword.get(opts, :message_value))

            case Ide.Debugger.RuntimeExecutor.execute(step_request) do
              {:ok, step_payload} ->
                {:cont, {:ok, get_in(step_payload.model_patch, ["runtime_model"]) || model}}

              {:error, reason} ->
                {:halt, {:compile_error, reason}}
            end
          end)
          |> case do
            {:ok, final_model} -> {:ok, manifest, final_model}
            {:compile_error, _} = err -> err
          end
        else
          {:error, reason} -> {:compile_error, reason}
          _ -> {:compile_error, :init_failed}
        end

      {:error, reason} ->
        {:compile_error, reason}
    end
  end

  @doc """
  Applies `cmd.companion.bridge` init followups from an executor payload, mirroring
  debugger simulator bridge responses (subscription-style APIs, storage, preferences).
  """
  @spec corpus_apply_companion_bridge_init_followups(map(), map(), map(), keyword()) :: map()
  def corpus_apply_companion_bridge_init_followups(
        init_request,
        runtime_model,
        init_payload,
        opts \\ []
      )
      when is_map(init_request) and is_map(runtime_model) and is_map(init_payload) do
    settings = Keyword.get(opts, :simulator_settings, DebuggerSimulatorSettings.default())

    init_payload
    |> Map.get(:followup_messages, Map.get(init_payload, "followup_messages", []))
    |> List.wrap()
    |> Enum.reduce(runtime_model, fn row, model ->
      case companion_bridge_followup_step(row, settings) do
        {message, message_value} when is_binary(message) ->
          step_request =
            init_request
            |> Map.put(:current_model, %{"runtime_model" => model})
            |> Map.put(:message, message)
            |> Map.put(:message_value, message_value)

          case Ide.Debugger.RuntimeExecutor.execute(step_request) do
            {:ok, step_payload} ->
              get_in(step_payload.model_patch, ["runtime_model"]) || model

            {:error, _} ->
              model
          end

        _ ->
          model
      end
    end)
  end

  @spec companion_bridge_followup_step(map(), map()) :: {String.t(), map()} | nil
  defp companion_bridge_followup_step(row, settings) when is_map(row) and is_map(settings) do
    source = Map.get(row, "source") || Map.get(row, :source)
    package = Map.get(row, "package") || Map.get(row, :package)

    if source == "companion_bridge_command" or package == "pebble/companion" do
      command = Map.get(row, "command") || Map.get(row, :command) || %{}

      callback =
        Map.get(command, "callback_constructor") || Map.get(row, "message") ||
          Map.get(row, :message)

      existing_value = Map.get(row, "message_value") || Map.get(row, :message_value)

      with true <- is_binary(callback) and callback != "",
           {:ok, message_value} <-
             companion_bridge_message_value(callback, command, existing_value, settings) do
        {callback, message_value}
      else
        _ -> nil
      end
    else
      nil
    end
  end

  @spec companion_bridge_message_value(String.t(), map(), term(), map()) ::
          {:ok, map()} | :error
  defp companion_bridge_message_value(callback, command, _existing_value, settings)
       when is_binary(callback) and is_map(command) and is_map(settings) do
    case companion_bridge_callback_result(command, settings) do
      {:ok, result} ->
        {result_ctor, payload} = CompanionBridge.callback_result_parts(result)
        {:ok, CompanionBridge.subscription_result_message_value(callback, result_ctor, payload)}

      :error ->
        :error
    end
  end

  @spec companion_bridge_callback_result(map(), map()) ::
          {:ok, {:ok, term()} | {:error, String.t()}} | :error
  defp companion_bridge_callback_result(command, settings)
       when is_map(command) and is_map(settings) do
    api = Map.get(command, "api") || Map.get(command, :api)
    op = Map.get(command, "op") || Map.get(command, :op)

    request = %{
      op: op,
      key: Map.get(command, "key") || Map.get(command, :key),
      value: Map.get(command, "value") || Map.get(command, :value)
    }

    cond do
      api == "storage" ->
        {_settings, result} = SimulatorStore.storage_result(settings, request)
        {:ok, result}

      api == "preferences" ->
        {_settings, result} = SimulatorStore.preferences_result(settings, request)
        {:ok, result}

      api == "webSocket" ->
        {:ok, {:ok, companion_wire_unit()}}

      is_binary(api) ->
        case CompanionBridge.contract_for_source(api) do
          %{} = contract ->
            payload = CompanionBridge.payload(settings, Map.fetch!(contract, :payload), request)
            {:ok, {:ok, payload}}

          _ ->
            :error
        end

      true ->
        :error
    end
  end

  defp maybe_put_message_value(request, nil), do: request

  defp maybe_put_message_value(request, message_value),
    do: Map.put(request, :message_value, message_value)
end
