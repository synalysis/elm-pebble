defmodule Ide.TestSupport.McpDebuggerFlow do
  @moduledoc false

  import ExUnit.Assertions

  alias Ide.Mcp.Tools
  alias Ide.Projects

  @watch_source """
  module Main exposing (..)

  type Msg
      = Inc
      | Tick

  init _ =
      ( { n = 0 }, Cmd.none )

  update msg model =
      case msg of
          Inc ->
              ( { model | n = model.n + 1 }, Cmd.none )

          Tick ->
              ( model, Cmd.none )

  subscriptions _ =
      Time.every 1000 Tick

  view model =
      []
  """

  @phone_source """
  module Main exposing (..)

  type Msg
      = Sync

  init _ =
      ( { ok = False }, Cmd.none )

  view _ =
      []
  """

  @snap_source """
  module Main exposing (..)

  type Msg
      = A

  init _ =
      ( { n = 1 }, Cmd.none )

  view m =
      Ui.root []
  """

  @spec create_project!(map()) :: Projects.project()
  def create_project!(attrs \\ %{}) when is_map(attrs) do
    defaults = %{
      "name" => "McpDebugger",
      "slug" => "mcp-debugger-#{System.unique_integer([:positive])}",
      "target_type" => "app"
    }

    {:ok, project} = Projects.create_project(Map.merge(defaults, attrs))
    project
  end

  @spec start_session!(Projects.project()) :: map()
  def start_session!(project) do
    {:ok, %{state: started}} = Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])
    started
  end

  @spec reload_watch_and_phone!(Projects.project()) :: %{after_reload: map(), phone_reload: map()}
  def reload_watch_and_phone!(project) do
    {:ok, %{state: after_reload}} =
      Tools.call(
        "debugger.reload",
        %{
          "slug" => project.slug,
          "rel_path" => "watch/src/Main.elm",
          "source" => @watch_source,
          "reason" => "mcp_test"
        },
        [:edit]
      )

    {:ok, %{state: phone_reload}} =
      Tools.call(
        "debugger.reload",
        %{
          "slug" => project.slug,
          "rel_path" => "phone/Main.elm",
          "source" => @phone_source,
          "source_root" => "phone"
        },
        [:edit]
      )

    %{after_reload: after_reload, phone_reload: phone_reload}
  end

  @spec step_watch_and_tick!(Projects.project()) :: %{stepped: map(), ticked: map()}
  def step_watch_and_tick!(project) do
    {:ok, %{state: stepped}} =
      Tools.call(
        "debugger.step",
        %{"slug" => project.slug, "target" => "watch", "message" => "Inc", "count" => 2},
        [:edit]
      )

    {:ok, %{state: ticked}} =
      Tools.call(
        "debugger.tick",
        %{"slug" => project.slug, "target" => "watch", "count" => 1},
        [:edit]
      )

    %{stepped: stepped, ticked: ticked}
  end

  @spec bootstrap_stepped!(Projects.project()) :: %{
          started: map(),
          after_reload: map(),
          phone_reload: map(),
          stepped: map(),
          ticked: map()
        }
  def bootstrap_stepped!(project) do
    started = start_session!(project)
    %{after_reload: after_reload, phone_reload: phone_reload} = reload_watch_and_phone!(project)
    assert after_reload.seq > started.seq
    %{stepped: stepped, ticked: ticked} = step_watch_and_tick!(project)
    assert stepped.seq > phone_reload.seq

    %{
      started: started,
      after_reload: after_reload,
      phone_reload: phone_reload,
      stepped: stepped,
      ticked: ticked
    }
  end

  @spec reload_introspect_snapshot!(Projects.project()) :: map()
  def reload_introspect_snapshot!(project) do
    {:ok, %{state: intro_reload}} =
      Tools.call(
        "debugger.reload",
        %{
          "slug" => project.slug,
          "rel_path" => "watch/src/Main.elm",
          "source" => @snap_source,
          "source_root" => "watch",
          "reason" => "mcp_introspect"
        },
        [:edit]
      )

    intro_reload
  end

  @spec assert_replay_drift_band(String.t(), String.t(), non_neg_integer(), String.t()) :: :ok
  def assert_replay_drift_band(slug, replay_drift_seq, expected_seq, expected_band) do
    assert {:ok, %{state: replayed}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_drift_seq" => replay_drift_seq
               },
               [:edit]
             )

    assert replay_event = Enum.find(replayed.events, &(&1.type == "debugger.replay"))
    telemetry = Map.get(replay_event.payload, :replay_telemetry)
    assert telemetry.drift_seq == expected_seq
    assert telemetry.drift_band == expected_band
  end
end
