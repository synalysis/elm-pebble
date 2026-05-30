defmodule Ide.DebuggerIntegrationExecutors do
  @moduledoc false

  defmodule DebuggerRuntimeExecutor do
      @moduledoc false

      def execute(request) when is_map(request) do
        selected_n = get_in(request, [:current_model, "runtime_model", "n"])
        artifact_version = get_in(request, [:elm_executor_metadata, "version"])

        {:ok,
         %{
           model_patch: %{"rendered_n" => selected_n, "artifact_version" => artifact_version},
           view_tree: %{"type" => "runtime-root", "children" => [%{"n" => selected_n}]},
           view_output: [%{"kind" => "text_label", "x" => selected_n, "y" => 2, "text" => "ok"}]
         }}
      end
    end
  defmodule TupleMaybeRuntimeExecutor do
      @moduledoc false

      def execute(request) when is_map(request) do
        runtime_model = get_in(request, [:current_model, "runtime_model"]) || %{}
        message = Map.get(request, :message) || ""

        runtime_model =
          cond do
            String.starts_with?(message, "CurrentDateTime ") ->
              Map.put(runtime_model, "currentDateTime", {
                1,
                %{
                  "year" => 2026,
                  "month" => 4,
                  "day" => 25,
                  "dayOfWeek" => %{"ctor" => "Sat", "args" => []},
                  "hour" => 21,
                  "minute" => 19,
                  "second" => 0,
                  "utcOffsetMinutes" => -360
                }
              })

            message == "" ->
              Map.put(runtime_model, "currentDateTime", %{"ctor" => "Nothing", "args" => []})

            true ->
              runtime_model
          end

        {:ok,
         %{
           model_patch: %{
             "runtime_model" => runtime_model,
             "runtime_model_source" => "tuple_maybe_test"
           },
           view_tree: %{"type" => "tuple-maybe-runtime", "children" => []},
           view_output: []
         }}
      end
    end
  defmodule HttpFollowupRuntimeExecutor do
      @moduledoc false

      def execute(%{message: "Tick"}) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"lastResponse" => 0}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: [
             %{
               "source" => "http_command",
               "package" => "elm/http",
               "message" => "WeatherReceived <GET https://example.test/weather>",
               "command" => %{
                 "kind" => "http",
                 "method" => "GET",
                 "url" => "https://example.test/weather",
                 "headers" => [],
                 "body" => %{"kind" => "empty"},
                 "expect" => %{
                   "kind" => "string",
                   "to_msg" => {:function_ref, "WeatherReceived"}
                 }
               }
             }
           ]
         }}
      end

      def execute(%{message_value: %{"ctor" => "WeatherReceived"} = message_value}) do
        {:ok,
         %{
           model_patch: %{
             "runtime_model" => %{
               "lastResponse" => 1,
               "received" => message_value
             }
           },
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: []
         }}
      end

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: []
         }}
      end
    end
  defmodule InitRandomFollowupRuntimeExecutor do
      @moduledoc false

      def execute(%{
            message: "RandomGenerated",
            message_value: %{"ctor" => "RandomGenerated"} = value
          }) do
        {:ok,
         %{
           model_patch: %{
             "runtime_model" => %{
               "cells" => [0, 2],
               "seed" => value["args"] |> List.first()
             }
           },
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: []
         }}
      end

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"cells" => [], "seed" => 0}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: [
             %{
               "source" => "random_command",
               "package" => "elm/random",
               "message" => "RandomGenerated",
               "message_value" => %{"ctor" => "RandomGenerated", "args" => [42]},
               "command" => %{"kind" => "cmd.random.generate"}
             }
           ]
         }}
      end
    end
  defmodule StorageFollowupRuntimeExecutor do
      @moduledoc false

      def execute(%{message: "SaveBest"}) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"best" => 9124}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: [
             %{
               "source" => "storage_command",
               "package" => "elm-pebble/elm-watch",
               "message" => nil,
               "command" => %{
                 "kind" => "cmd.storage.write_string",
                 "key" => 2048,
                 "value" => "9124"
               }
             }
           ]
         }}
      end

      def execute(%{
            message: "BestLoaded",
            message_value: %{"ctor" => "BestLoaded", "args" => [value]}
          }) do
        best =
          case Integer.parse(to_string(value || "0")) do
            {parsed, _rest} -> parsed
            :error -> 0
          end

        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"best" => best}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: []
         }}
      end

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"best" => 0}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           protocol_events: [],
           followup_messages: [
             %{
               "source" => "storage_command",
               "package" => "elm-pebble/elm-watch",
               "message" => "BestLoaded",
               "message_value" => %{"ctor" => "BestLoaded", "args" => [""]},
               "command" => %{
                 "kind" => "cmd.storage.read_string",
                 "key" => 2048,
                 "value" => "",
                 "message" => "BestLoaded",
                 "message_value" => %{"ctor" => "BestLoaded", "args" => [""]}
               }
             }
           ]
         }}
      end
    end
  defmodule FailingExternalRuntimeExecutor do
      @moduledoc false

      def execute(_request), do: {:error, :forced_runtime_failure}
    end
  defmodule InitNoFollowupRuntimeExecutor do
      @moduledoc false

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{}},
           view_tree: %{"type" => "root", "children" => []},
           view_output: [],
           runtime: %{
             "execution_backend" => "external",
             "followup_message_count" => 0,
             "init_cmd_count" => 1
           },
           protocol_events: [],
           followup_messages: []
         }}
      end
    end
  defmodule NilMaybeRuntimeExecutor do
      @moduledoc false

      def execute(request) when is_map(request) do
        runtime_model =
          request
          |> get_in([:current_model, "runtime_model"])
          |> case do
            model when is_map(model) -> model
            _ -> %{}
          end
          |> Map.put("batteryLevel", nil)

        {:ok,
         %{
           model_patch: %{
             "runtime_model" => runtime_model,
             "runtime_model_source" => "nil_maybe_test"
           },
           view_tree: %{"type" => "nil-maybe-runtime", "children" => []},
           view_output: []
         }}
      end
    end
  defmodule MaybeShapeRuntimeExecutor do
      @moduledoc false

      def execute(request) when is_map(request) do
        runtime_model =
          request
          |> get_in([:current_model, "runtime_model"])
          |> case do
            model when is_map(model) -> model
            _ -> %{}
          end
          |> Map.merge(%{
            "backgroundColor" => 0,
            "batteryLevel" => 88,
            "condition" => {1, %{"ctor" => "Clear", "args" => []}},
            "connected" => {1, true},
            "temperature" => {1, %{"ctor" => "Celsius", "args" => [4]}}
          })

        {:ok,
         %{
           model_patch: %{
             "runtime_model" => runtime_model,
             "runtime_model_source" => "maybe_shape_test"
           },
           view_tree: %{"type" => "maybe-shape-runtime", "children" => []},
           view_output: []
         }}
      end
    end
  defmodule AccelRuntimeExecutor do
      @moduledoc false

      def execute(%{message_value: %{"ctor" => "AccelData", "args" => [%{} = sample]}}) do
        {:ok,
         %{
           model_patch: %{
             "runtime_model" => %{
               "x" => sample["x"],
               "y" => sample["y"],
               "z" => sample["z"]
             }
           },
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"x" => 0, "y" => 0, "z" => 1000}},
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end
    end
  defmodule FrameRuntimeExecutor do
      @moduledoc false

      def execute(%{message: "FrameTick " <> encoded}) do
        {:ok, frame} = Jason.decode(encoded)

        {:ok,
         %{
           model_patch: %{
             "runtime_model" => %{
               "frame" => frame["frame"],
               "dtMs" => frame["dtMs"],
               "elapsedMs" => frame["elapsedMs"]
             }
           },
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{}},
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end
    end
  defmodule AliveGuardFrameExecutor do
      @moduledoc false

      def execute(%{message: "Die"}) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{"alive" => "false"}},
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end

      def execute(%{message: "FrameTick " <> encoded}) do
        {:ok, frame} = Jason.decode(encoded)

        {:ok,
         %{
           model_patch: %{
             "runtime_model" => %{
               "frame" => frame["frame"],
               "dtMs" => frame["dtMs"],
               "elapsedMs" => frame["elapsedMs"]
             }
           },
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end

      def execute(_request) do
        {:ok,
         %{
           model_patch: %{"runtime_model" => %{}},
           view_tree: %{"type" => "runtime-root", "children" => []},
           view_output: []
         }}
      end
    end
end
