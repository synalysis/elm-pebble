defmodule Ide.Debugger.SurfaceCompileEphemeralTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.SurfaceCompileArtifacts

  test "ephemeral inline compile attaches versioned core ir to watch shell" do
    source =
      File.read!(
        Path.expand(
          "../../../../elmc/test/fixtures/pebble_surface_project/src/Main.elm",
          __DIR__
        )
      )

    state = %{
      scope_key: "ephemeral-test",
      watch: %{
        model: %{
          "last_source" => source,
          "last_path" => "watch/src/Main.elm",
          "source_root" => "watch"
        },
        shell: %{}
      }
    }

    ctx = %{
      session_key_from_state: fn _ -> "ephemeral-test" end,
      source_root_for_target: fn :watch -> "watch" end,
      merge_runtime_artifacts: fn st, target, fields ->
        Ide.Debugger.RuntimeArtifactMerge.maybe_merge(st, target, fields)
      end
    }

    artifacts = SurfaceCompileArtifacts.artifacts_for_source_root(state, "watch", ctx)

    assert is_binary(artifacts["elm_executor_core_ir_b64"]) and
             artifacts["elm_executor_core_ir_b64"] != "",
           "expected inline compile artifacts, got #{inspect(Map.keys(artifacts))}"

    next = SurfaceCompileArtifacts.ensure_attached(state, :watch, ctx)

    assert RuntimeArtifacts.versioned_core_ir?(RuntimeArtifacts.execution_model(get_in(next, [:watch]) || %{}))
  end

  test "ephemeral inline compile attaches versioned core ir to companion shell for phone source root" do
    source =
      File.read!(
        Path.expand(
          "../../../priv/project_templates/companion_demo_phone_status/phone/src/CompanionApp.elm",
          __DIR__
        )
      )

    state = %{
      scope_key: "ephemeral-phone-test",
      companion: %{
        model: %{
          "last_source" => source,
          "last_path" => "phone/src/CompanionApp.elm",
          "source_root" => "phone"
        },
        shell: %{}
      }
    }

    ctx = %{
      session_key_from_state: fn _ -> "ephemeral-phone-test" end,
      source_root_for_target: fn :companion -> "phone" end,
      merge_runtime_artifacts: fn st, target, fields ->
        Ide.Debugger.RuntimeArtifactMerge.maybe_merge(st, target, fields)
      end
    }

    artifacts = SurfaceCompileArtifacts.artifacts_for_source_root(state, "phone", ctx)

    assert is_binary(artifacts["elm_executor_core_ir_b64"]) and
             artifacts["elm_executor_core_ir_b64"] != ""

    next = SurfaceCompileArtifacts.ensure_attached(state, :companion, ctx)

    assert RuntimeArtifacts.versioned_core_ir?(
             RuntimeArtifacts.execution_model(get_in(next, [:companion]) || %{})
           )
  end

  test "inline compile core ir executes inc update with launch envelope" do
    source = """
    module Main exposing (..)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as Ui

    type alias Model =
        { n : Int, enabled : Bool }

    type Msg
        = Inc
        | Dec

    init _ =
        ( { n = 1, enabled = false }, Cmd.none )

    update msg model =
        case msg of
            Inc ->
                ( { n = model.n + 1, enabled = model.enabled }, Cmd.none )

            Dec ->
                ( { n = model.n - 1, enabled = model.enabled }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.root []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    state = %{
      scope_key: "ephemeral-inc",
      watch: %{
        model: %{
          "last_source" => source,
          "last_path" => "watch/src/Main.elm",
          "source_root" => "watch"
        },
        shell: %{}
      }
    }

    ctx = %{
      session_key_from_state: fn _ -> "ephemeral-inc" end,
      source_root_for_target: fn :watch -> "watch" end,
      merge_runtime_artifacts: fn st, target, fields ->
        Ide.Debugger.RuntimeArtifactMerge.maybe_merge(st, target, fields)
      end
    }

    artifacts = SurfaceCompileArtifacts.artifacts_for_source_root(state, "watch", ctx)
    assert is_binary(artifacts["elm_executor_core_ir_b64"])

    core_ir =
      artifacts["elm_executor_core_ir_b64"]
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: source,
      introspect: %{
        "msg_constructors" => ["Inc", "Dec"],
        "init_model" => %{"n" => 1, "enabled" => false}
      },
      current_model: %{
        "launch_context" => %{"screen" => %{"width" => 144, "height" => 168}},
        "runtime_model" => %{
          "n" => 1,
          "enabled" => %{"$var" => false},
          "screenW" => 144,
          "screenH" => 168
        }
      },
      current_view_tree: %{},
      message: "Inc",
      elm_executor_core_ir: core_ir,
      elm_executor_metadata: artifacts["elm_executor_metadata"] || %{"entry_module" => "Main"}
    }

    assert {:ok, result} = ElmExecutor.Runtime.SemanticExecutor.execute(request)

    assert result.runtime["operation_source"] == "core_ir_update_eval"
    assert result.model_patch["runtime_model"]["n"] == 2
  end
end
