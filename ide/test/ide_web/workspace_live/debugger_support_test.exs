defmodule IdeWeb.WorkspaceLive.DebuggerSupportTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  test "view_tree_outline renders nested watch view_tree" do
    runtime = %{
      view_tree: %{
        "type" => "root",
        "children" => [%{"type" => "child", "children" => []}]
      }
    }

    outline = DebuggerSupport.view_tree_outline(runtime)
    assert String.contains?(outline, "root")
    assert String.contains?(outline, "child")
  end

  test "assign_defaults includes replay form defaults" do
    socket = DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})
    assert socket.assigns.debugger_replay_form[:count].value == "1"
    assert socket.assigns.debugger_replay_form[:target].value == "all"
    assert socket.assigns.debugger_replay_form[:cursor_bound].value == "true"
    assert socket.assigns.debugger_replay_form[:mode].value == "frozen"
    assert socket.assigns.debugger_replay_preview_seq == nil
    assert socket.assigns.debugger_replay_live_warning == false
    assert socket.assigns.debugger_replay_live_drift == nil
    assert socket.assigns.debugger_last_replay == nil
    assert socket.assigns.debugger_compare_baseline_seq == nil
    assert socket.assigns.debugger_compare_form[:baseline_seq].value == ""
    assert socket.assigns.debugger_runtime_fingerprint_compare == nil
    assert socket.assigns.debugger_trace_export_context == nil
    assert socket.assigns.debugger_export_form[:compare_cursor_seq].value == ""
    assert socket.assigns.debugger_export_form[:baseline_cursor_seq].value == ""
    assert socket.assigns.debugger_advanced_debug_tools == false
    assert socket.assigns.debugger_trigger_buttons == []
    assert socket.assigns.debugger_watch_trigger_buttons == []
    assert socket.assigns.debugger_companion_trigger_buttons == []
    assert socket.assigns.debugger_timeline_mode == "mixed"
    assert socket.assigns.debugger_watch_auto_fire == false
    assert socket.assigns.debugger_companion_auto_fire == false
  end

  test "snapshot_runtime_at_cursor returns nearest runtime snapshots at or before cursor" do
    events = [
      %{seq: 5, type: "debugger.tick", watch: nil, companion: nil, phone: nil},
      %{seq: 4, watch: %{model: %{"v" => 4}}, companion: %{model: %{"v" => 40}}, phone: nil},
      %{seq: 2, watch: %{model: %{"v" => 2}}, companion: nil, phone: nil}
    ]

    runtime_latest = DebuggerSupport.snapshot_runtime_at_cursor(events, 5)
    assert runtime_latest.watch.model["v"] == 4
    assert runtime_latest.companion.model["v"] == 40
    assert runtime_latest.phone == nil

    runtime = DebuggerSupport.snapshot_runtime_at_cursor(events, 3)
    assert runtime.watch.model["v"] == 2
    assert runtime.companion == nil
    assert runtime.phone == nil
  end

  test "snapshot runtime falls back to live runtime when cursor has no snapshots" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> DebuggerSupport.assign_defaults()
      |> Phoenix.Component.assign(:debugger_state, %{
        events: [%{seq: 2, type: "debugger.tick", watch: nil, companion: nil, phone: nil}],
        watch: %{model: %{"v" => 9}, view_tree: %{"type" => "root", "children" => []}},
        companion: %{model: %{"v" => 19}, view_tree: %{"type" => "root", "children" => []}},
        phone: %{model: %{"v" => 29}, view_tree: %{"type" => "root", "children" => []}}
      })
      |> Phoenix.Component.assign(:debugger_cursor_seq, 2)

    moved = DebuggerSupport.step_forward(socket)
    assert moved.assigns.debugger_cursor_watch_runtime.model["v"] == 9
    assert moved.assigns.debugger_cursor_companion_runtime.model["v"] == 19
  end

  test "refresh_following_debugger_latest follows live tip but preserves historical selection" do
    slug = "support-debugger-follow-latest-#{System.unique_integer([:positive])}"
    {:ok, _} = Debugger.import_trace(slug, debugger_trace_body(slug, [debugger_row(1, 10)]))

    socket =
      %Phoenix.LiveView.Socket{}
      |> DebuggerSupport.assign_defaults()
      |> Phoenix.Component.assign(:project, %{slug: slug})
      |> DebuggerSupport.refresh()

    assert socket.assigns.debugger_cursor_seq == 1
    assert get_in(socket.assigns.debugger_watch_runtime, [:model, "runtime_model", "value"]) == 10

    {:ok, _} =
      Debugger.import_trace(
        slug,
        debugger_trace_body(slug, [debugger_row(2, 20), debugger_row(1, 10)])
      )

    followed = DebuggerSupport.refresh_following_debugger_latest(socket)
    assert followed.assigns.debugger_cursor_seq == 2

    assert get_in(followed.assigns.debugger_watch_runtime, [:model, "runtime_model", "value"]) ==
             20

    pinned = DebuggerSupport.set_debugger_cursor_seq(followed, 1)

    {:ok, _} =
      Debugger.import_trace(
        slug,
        debugger_trace_body(slug, [debugger_row(3, 30), debugger_row(2, 20), debugger_row(1, 10)])
      )

    preserved = DebuggerSupport.refresh_following_debugger_latest(pinned)
    assert preserved.assigns.debugger_cursor_seq == 1

    assert get_in(preserved.assigns.debugger_watch_runtime, [:model, "runtime_model", "value"]) ==
             10
  end

  test "refresh exposes watch subscription trigger buttons from parsed source" do
    slug = "support-debugger-watch-triggers-#{System.unique_integer([:positive])}"

    source = """
    module TriggerSubscriptions exposing (..)

    import Pebble.Events as Events

    type Msg
      = Tick
      | MinuteChanged Int

    init _ =
      ( {}, Cmd.none )

    update msg model =
      ( model, Cmd.none )

    subscriptions _ =
      Events.batch [ Events.onTick Tick, Events.onMinuteChange MinuteChanged ]
    """

    {:ok, _} = Debugger.start_session(slug)

    {:ok, _} =
      Debugger.reload(slug, %{
        rel_path: "watch/TriggerSubscriptions.elm",
        source: source,
        reason: "support_subscription_buttons"
      })

    socket =
      %Phoenix.LiveView.Socket{}
      |> DebuggerSupport.assign_defaults()
      |> Phoenix.Component.assign(:project, %{slug: slug})
      |> DebuggerSupport.refresh()

    assert Enum.any?(socket.assigns.debugger_watch_trigger_buttons, fn row ->
             row.trigger == "on_tick" and row.message == "Tick"
           end)

    assert Enum.any?(socket.assigns.debugger_watch_trigger_buttons, fn row ->
             row.trigger == "on_minute_change" and row.message == "MinuteChanged"
           end)

    assert socket.assigns.debugger_companion_trigger_buttons == []
  end

  test "debugger_rows derives selected and paired watch companion snapshots" do
    events = [
      %{
        seq: 7,
        type: "debugger.elmc_compile",
        payload: %{},
        watch: %{model: %{"runtime_model" => %{"w" => 7}}, view_tree: %{"type" => "resolved"}},
        companion: %{model: %{"runtime_model" => %{"c" => 6}}},
        phone: nil
      },
      %{
        seq: 6,
        type: "debugger.update_in",
        payload: %{target: "companion", message: "Sync"},
        watch: %{model: %{"runtime_model" => %{"w" => 5}}},
        companion: %{model: %{"runtime_model" => %{"c" => 6}}},
        phone: nil
      },
      %{
        seq: 5,
        type: "debugger.update_in",
        payload: %{target: "watch", message: "Tick"},
        watch: %{model: %{"runtime_model" => %{"w" => 5}}},
        companion: nil,
        phone: nil
      },
      %{
        seq: 4,
        type: "debugger.init_in",
        payload: %{target: "watch", message: "init", message_source: "init"},
        watch: %{model: %{"runtime_model" => %{"w" => 1}}},
        companion: nil,
        phone: nil
      },
      %{
        seq: 3,
        type: "debugger.update_in",
        payload: %{target: "companion", message: "Boot"},
        watch: nil,
        companion: %{model: %{"runtime_model" => %{"c" => 3}}},
        phone: nil
      }
    ]

    rows = DebuggerSupport.debugger_rows(events)
    assert Enum.map(rows, & &1.seq) == [1, 2, 3, 4]
    assert Enum.map(rows, & &1.raw_seq) == [3, 4, 5, 6]

    init_row = Enum.find(rows, &(&1.raw_seq == 4))
    assert init_row.target == "watch"
    assert init_row.message == "init"
    assert init_row.message_source == "init"
    assert get_in(init_row.selected_runtime, [:model, "runtime_model", "w"]) == 1

    watch_row = Enum.find(rows, &(&1.raw_seq == 5))
    assert watch_row.target == "watch"
    assert get_in(watch_row.selected_runtime, [:model, "runtime_model", "w"]) == 5
    refute get_in(watch_row.selected_runtime, [:view_tree, "type"]) == "resolved"
    assert get_in(watch_row.other_runtime, [:model, "runtime_model", "c"]) == 3

    companion_row = DebuggerSupport.selected_debugger_row(events, 4)
    assert companion_row.target == "companion"
    assert get_in(companion_row.selected_runtime, [:model, "runtime_model", "c"]) == 6
    assert get_in(companion_row.other_runtime, [:model, "runtime_model", "w"]) == 5
  end

  test "debugger_rows reads semantic debugger timeline snapshots without raw seq gaps" do
    state = %{
      debugger_timeline: [
        %{
          seq: 3,
          raw_seq: 42,
          type: "update",
          target: "watch",
          message: "HourChanged 21",
          message_source: "subscription_trigger",
          watch: %{model: %{"runtime_model" => %{"hour" => 21}}},
          companion: %{model: %{"runtime_model" => %{"synced" => true}}},
          phone: nil
        },
        %{
          seq: 2,
          raw_seq: 17,
          type: "update",
          target: "companion",
          message: "Sync",
          message_source: "protocol_rx",
          watch: %{model: %{"runtime_model" => %{"hour" => 12}}},
          companion: %{model: %{"runtime_model" => %{"synced" => true}}},
          phone: nil
        },
        %{
          seq: 1,
          raw_seq: 4,
          type: "init",
          target: "watch",
          message: "init",
          message_source: "init",
          watch: %{model: %{"runtime_model" => %{"hour" => 12}}},
          companion: %{model: %{"runtime_model" => %{"synced" => false}}},
          phone: nil
        }
      ],
      events: []
    }

    rows = DebuggerSupport.debugger_rows(state)
    assert Enum.map(rows, & &1.seq) == [3, 2, 1]
    assert Enum.map(rows, & &1.raw_seq) == [42, 17, 4]

    selected = DebuggerSupport.selected_debugger_row(state, 3)
    assert selected.message == "HourChanged 21"
    assert get_in(selected.watch_runtime, [:model, "runtime_model", "hour"]) == 21
    assert get_in(selected.companion_runtime, [:model, "runtime_model", "synced"]) == true
  end

  test "debugger timeline row helpers filter watch companion and mixed modes" do
    rows = [
      %{seq: 1, target: "watch", message: "Tick"},
      %{seq: 2, target: "companion", message: "Sync"},
      %{seq: 3, target: "watch", message: "Button"}
    ]

    watch_rows = DebuggerSupport.debugger_rows_for_mode(rows, "watch")
    companion_rows = DebuggerSupport.debugger_rows_for_mode(rows, "companion")
    mixed_rows = DebuggerSupport.debugger_rows_for_mode(rows, "mixed")

    assert Enum.map(watch_rows, & &1.seq) == [3, 1]
    assert Enum.map(companion_rows, & &1.seq) == [2]
    assert Enum.map(mixed_rows, & &1.seq) == [3, 2, 1]
    assert Enum.map(DebuggerSupport.debugger_rows_for_target(rows, "watch"), & &1.seq) == [3, 1]
  end

  test "debugger_timeline_text exports visible rows as raw lines" do
    rows = [
      %{seq: 1, target: "watch", type: "init", message: "init"},
      %{seq: 2, target: "companion", type: "update", message: "Sync {\"ok\":true}"}
    ]

    assert DebuggerSupport.debugger_timeline_text(rows) ==
             "#2 [companion] update Sync {\"ok\":true}\n#1 [watch] init init"
  end

  test "copy_json exports debugger payloads as pretty JSON" do
    assert DebuggerSupport.copy_json(%{"model" => %{"count" => 2}}) ==
             "{\n  \"model\": {\n    \"count\": 2\n  }\n}"
  end

  test "set_debugger_timeline_mode normalizes supported timeline modes" do
    socket = DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})

    assert DebuggerSupport.set_debugger_timeline_mode(socket, "watch").assigns.debugger_timeline_mode ==
             "watch"

    assert DebuggerSupport.set_debugger_timeline_mode(socket, "companion").assigns.debugger_timeline_mode ==
             "companion"

    assert DebuggerSupport.set_debugger_timeline_mode(socket, "separate").assigns.debugger_timeline_mode ==
             "separate"

    assert DebuggerSupport.set_debugger_timeline_mode(socket, "bad").assigns.debugger_timeline_mode ==
             "mixed"
  end

  test "debugger_message_label formats constructor JSON payloads as Elm-like values" do
    message =
      ~s(CurrentDateTime {"day":24,"dayOfWeek":{"args":[],"ctor":"Fri"},"hour":20,"minute":0,"month":4,"second":39,"utcOffsetMinutes":-360,"year":2026})

    label = DebuggerSupport.debugger_message_label(message)

    assert label =~ "CurrentDateTime {"
    assert label =~ "day = 24"
    assert label =~ "dayOfWeek = Fri"
    assert label =~ "hour = 20"
    assert label =~ "utcOffsetMinutes = -360"
    refute label =~ ~s("ctor")
  end

  test "rendered_view_preview formats node type, labels, and children" do
    runtime = %{
      view_tree: %{
        "type" => "Window",
        "label" => "root",
        "children" => [%{"type" => "TextLayer", "text" => "Hello", "children" => []}]
      }
    }

    preview = DebuggerSupport.rendered_view_preview(runtime)
    assert preview =~ "- Window [root]"
    assert preview =~ "- TextLayer [Hello]"
  end

  test "rendered_view_preview labels argument values from structured arg metadata" do
    runtime = %{
      view_tree: %{
        "type" => "line",
        "arg_names" => ["x1", "y1", "x2", "y2", "color"],
        "children" => [
          %{"type" => "expr", "value" => 72, "children" => []},
          %{"type" => "expr", "value" => 84, "children" => []},
          %{"type" => "expr", "value" => 72, "children" => []},
          %{"type" => "expr", "value" => 23, "children" => []},
          %{"type" => "expr", "value" => 1, "children" => []}
        ]
      }
    }

    preview = DebuggerSupport.rendered_view_preview(runtime)
    assert preview =~ "- line"
    assert preview =~ "- 72 [x1]"
    assert preview =~ "- 84 [y1]"
    assert preview =~ "- 72 [x2]"
    assert preview =~ "- 23 [y2]"
    assert preview =~ "- 1 [color]"
    refute preview =~ "expr [23]"
  end

  test "rendered_view_preview annotates source expressions with evaluated values" do
    runtime = %{
      model: %{"runtime_model" => %{"screenW" => 144}},
      view_tree: %{
        "type" => "line",
        "arg_names" => ["startPos", "endPos", "color"],
        "children" => [
          %{
            "type" => "record",
            "children" => [
              %{
                "type" => "field",
                "label" => "x",
                "children" => [
                  %{
                    "type" => "call",
                    "label" => "__idiv__",
                    "children" => [
                      %{
                        "type" => "expr",
                        "label" => "model.screenW",
                        "op" => "field_access",
                        "children" => []
                      },
                      %{"type" => "expr", "value" => 2, "op" => "int_literal", "children" => []}
                    ]
                  }
                ]
              }
            ]
          },
          %{"type" => "record", "children" => []},
          %{"type" => "var", "label" => "color", "children" => []}
        ]
      }
    }

    preview = DebuggerSupport.rendered_view_preview(runtime)
    assert preview =~ "record [startPos]"
    assert preview =~ "field [x] [72]"
    assert preview =~ "call [__idiv__] [72]"
    assert preview =~ "expr [model.screenW] [144]"
  end

  test "rendered_view_preview does not invent primitive arg labels without metadata" do
    runtime = %{
      view_tree: %{
        "type" => "line",
        "children" => [
          %{"type" => "expr", "value" => 72, "children" => []},
          %{"type" => "expr", "value" => 84, "children" => []},
          %{"type" => "expr", "value" => 72, "children" => []},
          %{"type" => "expr", "value" => 23, "children" => []},
          %{"type" => "expr", "value" => 1, "children" => []}
        ]
      }
    }

    preview = DebuggerSupport.rendered_view_preview(runtime)
    assert preview =~ "- line"
    refute preview =~ "[x1]"
    refute preview =~ "[color]"
  end

  test "rendered_view_preview hides debugger runtime marker rows" do
    runtime = %{
      view_tree: %{
        "type" => "windowStack",
        "children" => [
          %{"type" => "debuggerRenderStep", "label" => "watch:Tick", "children" => []},
          %{"type" => "elmcRuntimeStep", "label" => "watch:Tick", "children" => []},
          %{"type" => "TextLayer", "text" => "1234", "children" => []}
        ]
      }
    }

    preview = DebuggerSupport.rendered_view_preview(runtime)
    refute preview =~ "debuggerRenderStep"
    refute preview =~ "elmcRuntimeStep"
    assert preview =~ "TextLayer [1234]"
  end

  test "rendered_view_preview includes runtime_view_output resolved values when present" do
    runtime = %{
      model: %{
        "runtime_view_output" => [
          %{
            "kind" => "round_rect",
            "x" => 16,
            "y" => 56,
            "w" => 112,
            "h" => 56,
            "radius" => 12,
            "fill" => 1
          },
          %{"kind" => "text_int", "x" => 36, "y" => 93, "text" => "1626"}
        ]
      },
      view_tree: %{"type" => "root", "children" => []}
    }

    preview = DebuggerSupport.rendered_view_preview(runtime)
    assert preview =~ "roundRect [x=16, y=56, w=112, h=56, r=12, fill=1]"
    assert preview =~ "textInt [x=36, y=93, 1626]"
  end

  test "debugger preview dimensions prefer launch context screen over stale tree box" do
    runtime = %{
      model: %{
        "launch_context" => %{
          "screen" => %{"width" => 200, "height" => 228}
        }
      }
    }

    tree = %{"type" => "window", "box" => %{"w" => 144, "h" => 168}, "children" => []}

    assert DebuggerPreview.screen_dimensions(runtime, tree) == {200, 228}
  end

  test "debugger preview dimensions fall back to launch context before tree box" do
    runtime = %{
      model: %{
        "launch_context" => %{
          "screen" => %{"width" => 180, "height" => 180}
        }
      }
    }

    tree = %{"type" => "window", "box" => %{"w" => 144, "h" => 168}, "children" => []}

    assert DebuggerPreview.screen_dimensions(runtime, tree) == {180, 180}
  end

  test "debugger preview shape follows launch context round screen contract" do
    runtime = %{
      model: %{
        "launch_context" => %{
          "screen" => %{"width" => 180, "height" => 180, "isRound" => true}
        }
      }
    }

    refute DebuggerPreview.screen_round?(%{
             model: %{"launch_context" => %{"screen" => %{"isRound" => false}}}
           })

    assert DebuggerPreview.screen_round?(runtime)
  end

  test "debugger preview shape falls back to launch context screen" do
    runtime = %{
      model: %{
        "launch_context" => %{
          "screen" => %{"width" => 180, "height" => 180, "isRound" => true}
        }
      }
    }

    assert DebuggerPreview.screen_round?(runtime)
  end

  test "debugger preview applies text color from runtime style context" do
    runtime = %{
      model: %{
        "runtime_view_output" => [
          %{"kind" => "clear", "color" => 192},
          %{"kind" => "push_context"},
          %{"kind" => "text_color", "color" => 255},
          %{"kind" => "text", "x" => 0, "y" => 24, "text" => "visible"},
          %{"kind" => "pop_context"},
          %{"kind" => "text", "x" => 0, "y" => 48, "text" => "default"}
        ]
      }
    }

    [clear, visible, default] = DebuggerPreview.svg_ops(nil, runtime)

    assert clear.kind == :clear
    assert visible.kind == :text_label
    assert visible.text_color == 255
    assert default.kind == :text_label
    assert default.text_color == nil
  end

  test "debugger preview preserves text bounds for centered SVG text" do
    runtime = %{
      model: %{
        "runtime_view_output" => [
          %{
            "kind" => "text",
            "x" => 0,
            "y" => 52,
            "w" => 180,
            "h" => 56,
            "text" => "--:--"
          }
        ]
      }
    }

    [text] = DebuggerPreview.svg_ops(nil, runtime)

    assert text.kind == :text_label
    assert text.x == 0
    assert text.w == 180
    assert text.h == 56
    assert text.font_size == 56
    assert text.text_align == "center"
  end

  test "debugger preview restores parent style after nested contexts" do
    runtime = %{
      model: %{
        "runtime_view_output" => [
          %{"kind" => "push_context"},
          %{"kind" => "fill_color", "color" => 204},
          %{"kind" => "fill_rect", "x" => 1, "y" => 2, "w" => 3, "h" => 4, "fill" => 1},
          %{"kind" => "push_context"},
          %{"kind" => "fill_color", "color" => 255},
          %{"kind" => "fill_rect", "x" => 5, "y" => 6, "w" => 7, "h" => 8, "fill" => 1},
          %{"kind" => "pop_context"},
          %{"kind" => "fill_rect", "x" => 9, "y" => 10, "w" => 11, "h" => 12, "fill" => 1},
          %{"kind" => "pop_context"}
        ]
      }
    }

    rows = DebuggerPreview.svg_ops(nil, runtime)

    assert Enum.map(rows, & &1.fill_color) == [204, 255, 204]
  end

  test "replay_preview_rows respects target and cursor bounds" do
    events = [
      %{seq: 6, type: "debugger.update_in", payload: %{target: "watch", message: "Inc"}},
      %{seq: 5, type: "debugger.update_in", payload: %{target: "companion", message: "Sync"}},
      %{seq: 4, type: "debugger.update_in", payload: %{target: "watch", message: "Dec"}},
      %{seq: 3, type: "debugger.reload", payload: %{}}
    ]

    rows =
      DebuggerSupport.replay_preview_rows(events, %{
        count: 2,
        target: "watch",
        cursor_seq: 5
      })

    assert rows == [%{seq: 4, target: "watch", message: "Dec"}]
  end

  test "replay_metadata_at_cursor resolves most recent replay at cursor" do
    events = [
      %{
        seq: 9,
        type: "debugger.replay",
        payload: %{
          target: "watch",
          replay_source: "frozen_preview",
          replay_telemetry: %{
            mode: "frozen",
            source: "frozen_preview",
            drift_seq: 0,
            drift_band: "none",
            used_live_query: false,
            used_frozen_preview: true
          },
          requested_count: 2,
          replayed_count: 1,
          cursor_seq: 7,
          replay_target_counts: %{"watch" => 1},
          replay_message_counts: %{"Inc" => 1},
          replay_preview: [%{seq: 6, target: "watch", message: "Inc"}]
        }
      },
      %{seq: 8, type: "debugger.update_in", payload: %{target: "watch", message: "Inc"}},
      %{
        seq: 7,
        type: "debugger.replay",
        payload: %{
          "target" => "protocol",
          "requested_count" => 1,
          "replayed_count" => 1,
          "replay_target_counts" => %{"protocol" => 1},
          "replay_message_counts" => %{"Sync" => 1},
          "replay_preview" => [%{"seq" => 5, "target" => "protocol", "message" => "Sync"}]
        }
      }
    ]

    replay_md = DebuggerSupport.replay_metadata_at_cursor(events, 9)
    assert replay_md.seq == 9
    assert replay_md.target == "watch"
    assert replay_md.replay_source == "frozen_preview"
    assert replay_md.replayed_count == 1

    assert_replay_telemetry(replay_md.replay_telemetry, %{
      mode: "frozen",
      source: "frozen_preview",
      drift_seq: 0,
      drift_band: "none",
      used_live_query: false,
      used_frozen_preview: true
    })

    assert %{seq: 7, target: "protocol", replayed_count: 1} =
             DebuggerSupport.replay_metadata_at_cursor(events, 7)
  end

  test "replay_compare reports match and mismatch states" do
    preview = [%{seq: 6, target: "watch", message: "Inc"}]

    assert %{status: :none, preview_count: 1, applied_count: 0} =
             DebuggerSupport.replay_compare(preview, nil)

    assert %{status: :match, preview_count: 1, applied_count: 1} =
             DebuggerSupport.replay_compare(preview, %{
               replayed_count: 1,
               replay_preview: [%{"seq" => 6, "target" => "watch", "message" => "Inc"}]
             })

    assert %{status: :mismatch, reason: "count", preview_count: 1, applied_count: 2} =
             DebuggerSupport.replay_compare(preview, %{
               replayed_count: 2,
               replay_preview: [%{"seq" => 6, "target" => "watch", "message" => "Inc"}]
             })
  end

  test "replay_compare includes first row mismatch details" do
    preview = [%{seq: 6, target: "watch", message: "Inc"}]

    assert %{
             status: :mismatch,
             reason: "rows",
             mismatch_preview: %{seq: 6, target: "watch", message: "Inc"},
             mismatch_applied: %{seq: 5, target: "watch", message: "Dec"}
           } =
             DebuggerSupport.replay_compare(preview, %{
               replayed_count: 1,
               replay_preview: [%{"seq" => 5, "target" => "watch", "message" => "Dec"}]
             })
  end

  test "replay_live_warning? detects timeline drift only for live mode" do
    events = [
      %{seq: 9, type: "debugger.update_in", payload: %{}},
      %{seq: 7, type: "debugger.update_in", payload: %{}}
    ]

    assert DebuggerSupport.replay_live_warning?("live", 7, events)
    refute DebuggerSupport.replay_live_warning?("frozen", 7, events)
    refute DebuggerSupport.replay_live_warning?("live", 9, events)
  end

  test "replay_live_drift returns drift size for live mode" do
    events = [
      %{seq: 12, type: "debugger.update_in", payload: %{}},
      %{seq: 9, type: "debugger.update_in", payload: %{}}
    ]

    assert DebuggerSupport.replay_live_drift("live", 9, events) == 3
    assert DebuggerSupport.replay_live_drift("live", 12, events) == nil
    assert DebuggerSupport.replay_live_drift("frozen", 9, events) == nil
  end

  test "replay_live_drift_severity buckets drift size" do
    assert DebuggerSupport.replay_live_drift_severity(nil) == :none
    assert DebuggerSupport.replay_live_drift_severity(1) == :mild
    assert DebuggerSupport.replay_live_drift_severity(3) == :mild
    assert DebuggerSupport.replay_live_drift_severity(4) == :medium
    assert DebuggerSupport.replay_live_drift_severity(10) == :medium
    assert DebuggerSupport.replay_live_drift_severity(11) == :high
  end

  test "replay_form_params returns safe defaults" do
    socket = DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})

    assert %{
             "count" => "1",
             "target" => "all",
             "cursor_bound" => "true",
             "mode" => "frozen"
           } = DebuggerSupport.replay_form_params(socket)
  end

  test "view_tree_outline handles nil runtime" do
    assert DebuggerSupport.view_tree_outline(nil) == "(no snapshot)"
  end

  test "rendered_tree prefers evaluated runtime view tree over parser wrapper outline" do
    runtime = %{
      view_tree: %{
        "type" => "windowStack",
        "children" => [%{"type" => "window", "children" => []}]
      },
      model: %{
        "elm_introspect" => %{
          "view_tree" => %{
            "type" => "toUiNode",
            "qualified_target" => "PebbleUi.toUiNode",
            "children" => [%{"type" => "append", "children" => []}]
          }
        }
      }
    }

    rendered = DebuggerSupport.rendered_tree(runtime)

    assert rendered["type"] == "windowStack"
    refute rendered["type"] == "toUiNode"
  end

  test "rendered_tree repairs normalized lowered Pebble Ui tuple trees" do
    runtime = %{
      view_tree: %{
        "type" => "tuple2",
        "label" => "",
        "children" => [
          %{"type" => "expr", "value" => 1, "children" => []},
          %{
            "type" => "List",
            "children" => [
              %{
                "type" => "tuple2",
                "children" => [
                  %{"type" => "expr", "value" => 1, "children" => []},
                  %{
                    "type" => "tuple2",
                    "children" => [
                      %{"type" => "expr", "value" => 1, "children" => []},
                      %{
                        "type" => "List",
                        "children" => [
                          %{
                            "type" => "tuple2",
                            "children" => [
                              %{"type" => "expr", "value" => 1, "children" => []},
                              %{
                                "type" => "tuple2",
                                "children" => [
                                  %{"type" => "expr", "value" => 1, "children" => []},
                                  %{
                                    "type" => "List",
                                    "children" => [
                                      %{
                                        "type" => "clear",
                                        "label" => "",
                                        "children" => [
                                          %{"type" => "expr", "value" => 192, "children" => []}
                                        ]
                                      }
                                    ]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
    }

    rendered = DebuggerSupport.rendered_tree(runtime)

    assert rendered["type"] == "windowStack"
    assert get_in(rendered, ["children", Access.at(0), "type"]) == "window"
    assert get_in(rendered, ["children", Access.at(0), "id"]) == 1

    layer = get_in(rendered, ["children", Access.at(0), "children", Access.at(0)])
    assert layer["type"] == "canvasLayer"
    assert layer["id"] == 1
    assert get_in(layer, ["children", Access.at(0), "color"]) == 192
    assert get_in(layer, ["children", Access.at(0), "children"]) == []
  end

  test "rendered_tree normalizes text charlists to strings" do
    runtime = %{
      view_tree: %{
        "type" => "text",
        "children" => [
          %{"type" => "expr", "value" => 1, "children" => []},
          %{"type" => "expr", "value" => 0, "children" => []},
          %{"type" => "expr", "value" => 52, "children" => []},
          %{"type" => "expr", "value" => 180, "children" => []},
          %{"type" => "expr", "value" => 56, "children" => []},
          %{"type" => "expr", "value" => ~c"22:31", "children" => []}
        ]
      }
    }

    rendered = DebuggerSupport.rendered_tree(runtime)

    assert rendered["text"] == "22:31"
    assert Jason.encode!(rendered) =~ ~s("text":"22:31")
  end

  test "rendered_node_bounds derives preview boxes from normalized rendered nodes" do
    tree = %{
      "type" => "windowStack",
      "children" => [
        %{
          "type" => "window",
          "children" => [
            %{
              "type" => "canvasLayer",
              "children" => [
                %{"type" => "clear", "color" => 192, "children" => []},
                %{"type" => "fillRect", "x" => 2, "y" => 3, "w" => 10, "h" => 8, "fill" => 255},
                %{"type" => "line", "x1" => 12, "y1" => 20, "x2" => 8, "y2" => 14, "color" => 0},
                %{"type" => "circle", "cx" => 30, "cy" => 40, "r" => 5, "color" => 0},
                %{
                  "type" => "arc",
                  "x" => 3,
                  "y" => 4,
                  "w" => 12,
                  "h" => 13,
                  "start_angle" => 0,
                  "end_angle" => 16_384
                },
                %{
                  "type" => "pathOutline",
                  "points" => [[1, 2], [7, 5], [3, 11]],
                  "offset_x" => 10,
                  "offset_y" => 20,
                  "rotation" => 0
                }
              ]
            }
          ]
        }
      ]
    }

    assert DebuggerSupport.rendered_node_bounds(tree, "0.0.0.0", 144, 168) ==
             %{x: 0, y: 0, w: 144, h: 168}

    assert DebuggerSupport.rendered_node_bounds(tree, "0.0.0.1", 144, 168) ==
             %{x: 2, y: 3, w: 10, h: 8}

    assert DebuggerSupport.rendered_node_bounds(tree, "0.0.0.2", 144, 168) ==
             %{x: 8, y: 14, w: 4, h: 6}

    assert DebuggerSupport.rendered_node_bounds(tree, "0.0.0.3", 144, 168) ==
             %{x: 25, y: 35, w: 10, h: 10}

    assert DebuggerSupport.rendered_node_bounds(tree, "0.0.0.4", 144, 168) ==
             %{x: 3, y: 4, w: 12, h: 13}

    assert DebuggerSupport.rendered_node_bounds(tree, "0.0.0.5", 144, 168) ==
             %{x: 11, y: 22, w: 6, h: 9}
  end

  test "rendered_node_summary includes promoted drawing command fields" do
    node = %{
      "type" => "roundRect",
      "x" => 50,
      "y" => 8,
      "w" => 100,
      "h" => 8,
      "radius" => 2,
      "fill" => 255,
      "children" => []
    }

    assert DebuggerSupport.rendered_node_summary(node, %{}) ==
             "roundRect (x=50, y=8, w=100, h=8, radius=2, fill=255 (white, #FFFFFFFF))"
  end

  test "rendered_node_summary resolves only declared color fields" do
    node = %{
      "type" => "fillRect",
      "x" => 2,
      "y" => 2,
      "w" => 3,
      "h" => 4,
      "fill" => 204,
      "children" => []
    }

    assert DebuggerSupport.rendered_node_summary(node, %{}) ==
             "fillRect (x=2, y=2, w=3, h=4, fill=204 (green, #00FF00FF))"
  end

  test "rendered_tree falls back to parser view tree when runtime tree is absent" do
    runtime = %{
      model: %{
        "elm_introspect" => %{
          "view_tree" => %{"type" => "root", "children" => [%{"type" => "text"}]}
        }
      }
    }

    assert DebuggerSupport.rendered_tree(runtime)["type"] == "root"
  end

  test "model_diagnostic_preview reads elmc_diagnostic_preview from runtime model" do
    runtime = %{
      model: %{"elmc_diagnostic_preview" => [%{"severity" => "error", "message" => "x"}]}
    }

    assert [%{"message" => "x"}] = DebuggerSupport.model_diagnostic_preview(runtime)
  end

  test "event_diagnostic_preview reads diagnostic_preview from event payload" do
    event = %{payload: %{diagnostic_preview: [%{"severity" => "info", "message" => "y"}]}}
    assert [%{"message" => "y"}] = DebuggerSupport.event_diagnostic_preview(event)
  end

  test "diagnostics_preview_at_cursor prefers event payload over embedded watch model" do
    events = [
      %{
        seq: 2,
        type: "debugger.elmc_check",
        payload: %{diagnostic_preview: [%{"message" => "from payload"}]},
        watch: %{model: %{"elmc_diagnostic_preview" => [%{"message" => "from model"}]}}
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    assert %{source: "event_payload", rows: [%{"message" => "from payload"}]} =
             DebuggerSupport.diagnostics_preview_at_cursor(events, 2)
  end

  test "format_elm_introspect_brief summarizes elm_introspect on a runtime map" do
    rt = %{
      model: %{
        "elm_executor_mode" => "runtime_executed",
        "elm_introspect" => %{
          "module" => "M",
          "source_byte_size" => 2048,
          "source_line_count" => 88,
          "module_exposing" => "..",
          "imported_modules" => ["Html", "Platform"],
          "import_entries" => [
            %{"module" => "Html", "as" => nil, "exposing" => nil},
            %{"module" => "Json.Decode", "as" => "Decode", "exposing" => ".."}
          ],
          "type_aliases" => ["Model"],
          "unions" => ["Msg", "Page"],
          "functions" => ["init", "update", "view", "subscriptions", "main"],
          "msg_constructors" => ["Inc", "Dec"],
          "update_case_branches" => ["Inc", "Dec"],
          "update_case_subject" => "msg",
          "update_cmd_ops" => ["Cmd.none"],
          "update_params" => ["msg", "model"],
          "subscription_ops" => ["onTick(T)", "Sub.none"],
          "main_program" => %{
            "target" => "Platform.worker",
            "kind" => "worker",
            "fields" => ["init", "update", "subscriptions"]
          },
          "init_model" => %{"n" => 0},
          "init_case_branches" => ["Public", "Secret"],
          "init_case_subject" => "flags",
          "init_cmd_ops" => ["Cmd.none"],
          "ports" => ["toJs", "fromJs"],
          "port_module" => true,
          "subscriptions_case_branches" => ["Home", "Settings"],
          "subscriptions_case_subject" => "model.page",
          "view_case_branches" => ["Home", "Settings"],
          "view_case_subject" => "model",
          "view_tree" => %{"type" => "windowStack", "children" => []}
        }
      }
    }

    out = DebuggerSupport.format_elm_introspect_brief(rt)
    assert out =~ "runtime_executed"
    assert out =~ "module: M"
    assert out =~ "source:"
    assert out =~ "2048 bytes"
    assert out =~ "88 lines"
    assert out =~ "exposing:"
    assert out =~ "(..)"
    assert out =~ "imports:"
    assert out =~ "import entries:"
    assert out =~ "Json.Decode as Decode (..)"
    assert out =~ "Html"
    assert out =~ "Platform"
    assert out =~ "type aliases:"
    assert out =~ "Model"
    assert out =~ "unions:"
    assert out =~ "Page"
    assert out =~ "functions:"
    assert out =~ "subscriptions"
    assert out =~ "Msg: Inc, Dec"
    assert out =~ "main:"
    assert out =~ "Platform.worker"
    assert out =~ "worker"
    assert out =~ "update (case msg):"
    assert out =~ "update Cmd:"
    assert out =~ "Inc, Dec"
    assert out =~ "subscriptions:"
    assert out =~ "ports:"
    assert out =~ "port module: yes"
    assert out =~ "toJs"
    assert out =~ "onTick"
    assert out =~ "init:"
    assert out =~ "init Cmd:"
    assert out =~ "Cmd.none"
    assert out =~ "view (case model):"
    assert out =~ "Home"
    assert out =~ "view root: windowStack"
    assert out =~ "update λ:"
    assert out =~ "msg, model"
  end

  test "elm_introspect_at_cursor reads elm_introspect from each embedded runtime" do
    events = [
      %{
        seq: 2,
        type: "debugger.reload",
        payload: %{},
        watch: %{model: %{"elm_introspect" => %{"module" => "W"}}},
        companion: %{model: %{"elm_introspect" => %{"module" => "C"}}},
        phone: %{model: %{}}
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    assert %{
             watch: %{"module" => "W"},
             companion: %{"module" => "C"},
             phone: nil
           } = DebuggerSupport.elm_introspect_at_cursor(events, 2)
  end

  test "diagnostics_preview_at_cursor falls back to companion when watch model has no diagnostics" do
    events = [
      %{
        seq: 2,
        type: "debugger.reload",
        payload: %{},
        watch: %{model: %{}},
        companion: %{model: %{"elmc_diagnostic_preview" => [%{"message" => "from companion"}]}},
        phone: %{model: %{}}
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    assert %{source: "cursor_model_companion", rows: [%{"message" => "from companion"}]} =
             DebuggerSupport.diagnostics_preview_at_cursor(events, 2)
  end

  test "diagnostics_preview_at_cursor falls back to phone after watch and companion empty" do
    events = [
      %{
        seq: 2,
        type: "debugger.reload",
        payload: %{},
        watch: %{model: %{}},
        companion: %{model: %{}},
        phone: %{model: %{"elmc_diagnostic_preview" => [%{"message" => "from phone"}]}}
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    assert %{source: "cursor_model_phone", rows: [%{"message" => "from phone"}]} =
             DebuggerSupport.diagnostics_preview_at_cursor(events, 2)
  end

  test "diagnostics_preview_source_label humanizes cursor sources" do
    assert DebuggerSupport.diagnostics_preview_source_label("cursor_model_companion") =~
             "companion"
  end

  test "event_summaries builds message for debugger.elm_introspect payload" do
    events = [
      %{
        seq: 1,
        type: "debugger.elm_introspect",
        payload: %{module: "M", target: "watch", view_root: "root"}
      }
    ]

    assert [%{message: msg}] = DebuggerSupport.event_summaries(events)
    assert msg =~ "M"
    assert msg =~ "watch"
    assert msg =~ "root"
  end

  test "runtime_fingerprints_at_cursor reads runtime fingerprint fields per surface" do
    events = [
      %{
        seq: 3,
        type: "debugger.runtime_exec",
        payload: %{},
        watch: %{
          model: %{
            "elm_executor_mode" => "runtime_executed",
            "runtime_model_source" => "init_model",
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64),
            "elm_executor" => %{
              "engine" => "elm_introspect_runtime_v1",
              "execution_backend" => "default",
              "view_tree_source" => "parser_view_tree",
              "runtime_model_entry_count" => 2,
              "view_tree_node_count" => 5
            }
          }
        },
        companion: %{model: %{}},
        phone: %{model: %{}}
      }
    ]

    fps = DebuggerSupport.runtime_fingerprints_at_cursor(events, 3)
    assert fps.watch.runtime_mode == "runtime_executed"
    assert fps.watch.engine == "elm_introspect_runtime_v1"
    assert fps.watch.execution_backend == "default"
    assert fps.watch.external_fallback_reason == nil
    assert fps.watch.runtime_model_source == "init_model"
    assert fps.watch.view_tree_source == "parser_view_tree"
    assert fps.watch.runtime_model_entry_count == 2
    assert fps.watch.view_tree_node_count == 5
    assert fps.watch.runtime_model_sha256 == String.duplicate("a", 64)
    assert fps.watch.view_tree_sha256 == String.duplicate("b", 64)
    assert fps.companion == nil
    assert fps.phone == nil
  end

  test "runtime_fingerprint_compare_at_cursor reports per-surface hash drift" do
    events = [
      %{
        seq: 3,
        type: "debugger.update_in",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64)
          }
        }
      },
      %{
        seq: 2,
        type: "debugger.update_in",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("c", 64),
            "runtime_view_tree_sha256" => String.duplicate("d", 64)
          }
        }
      }
    ]

    compare = DebuggerSupport.runtime_fingerprint_compare_at_cursor(events, 3, 2)
    assert compare.cursor_seq == 3
    assert compare.compare_cursor_seq == 2
    assert compare.changed_surface_count == 1
    assert compare.backend_changed_surface_count == 0
    assert compare.key_target_changed_surface_count == 0
    assert compare.drift_detail == nil
    assert compare.key_target_drift_detail == nil
    assert compare.surfaces.watch.changed == true
    assert compare.surfaces.watch.backend_changed == false
    assert compare.surfaces.watch.key_target_changed == false
    assert compare.surfaces.watch.current_model_sha == String.duplicate("a", 64)
    assert compare.surfaces.watch.compare_model_sha == String.duplicate("c", 64)
  end

  test "runtime_fingerprint_compare_at_cursor normalizes out-of-window cursors to in-window seqs" do
    events = [
      %{
        seq: 7,
        type: "debugger.update_in",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64)
          }
        }
      },
      %{
        seq: 4,
        type: "debugger.update_in",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("c", 64),
            "runtime_view_tree_sha256" => String.duplicate("d", 64)
          }
        }
      }
    ]

    compare = DebuggerSupport.runtime_fingerprint_compare_at_cursor(events, 6, 999)

    assert compare.cursor_seq == 4
    assert compare.compare_cursor_seq == 7
    assert compare.changed_surface_count == 1
    assert compare.surfaces.watch.current_model_sha == String.duplicate("c", 64)
    assert compare.surfaces.watch.compare_model_sha == String.duplicate("a", 64)
  end

  test "runtime_fingerprint_compare_at_cursor reports backend drift separately" do
    events = [
      %{
        seq: 3,
        type: "debugger.runtime_exec",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64),
            "elm_executor" => %{
              "execution_backend" => "external",
              "external_fallback_reason" => "{:external_runtime_executor_failed, :boom}"
            }
          }
        }
      },
      %{
        seq: 2,
        type: "debugger.runtime_exec",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64),
            "elm_executor" => %{"execution_backend" => "default"}
          }
        }
      }
    ]

    compare = DebuggerSupport.runtime_fingerprint_compare_at_cursor(events, 3, 2)
    assert compare.changed_surface_count == 1
    assert compare.backend_changed_surface_count == 1
    assert compare.key_target_changed_surface_count == 0
    assert is_binary(compare.drift_detail)
    assert compare.drift_detail =~ "backend:"
    assert compare.key_target_drift_detail == nil
    assert compare.surfaces.watch.changed == true
    assert compare.surfaces.watch.backend_changed == true
    assert compare.surfaces.watch.key_target_changed == false
    assert compare.surfaces.watch.current_execution_backend == "external"
    assert compare.surfaces.watch.compare_execution_backend == "default"

    assert compare.surfaces.watch.current_external_fallback_reason ==
             "{:external_runtime_executor_failed, :boom}"

    assert compare.surfaces.watch.compare_external_fallback_reason == nil
  end

  test "runtime_fingerprint_compare_at_cursor reports key-target provenance drift" do
    events = [
      %{
        seq: 3,
        type: "debugger.runtime_exec",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64),
            "elm_executor" => %{
              "target_numeric_key" => "count",
              "target_numeric_key_source" => "var_hint",
              "active_target_key" => "count",
              "active_target_key_source" => "var_hint"
            }
          }
        }
      },
      %{
        seq: 2,
        type: "debugger.runtime_exec",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64),
            "elm_executor" => %{
              "target_numeric_key" => "total",
              "target_numeric_key_source" => "primary_fallback",
              "active_target_key" => "total",
              "active_target_key_source" => "primary_fallback"
            }
          }
        }
      }
    ]

    compare = DebuggerSupport.runtime_fingerprint_compare_at_cursor(events, 3, 2)
    assert compare.changed_surface_count == 1
    assert compare.backend_changed_surface_count == 0
    assert compare.key_target_changed_surface_count == 1
    assert is_binary(compare.drift_detail)
    assert compare.drift_detail =~ "key-target:"
    assert is_binary(compare.key_target_drift_detail)
    assert compare.key_target_drift_detail =~ "watch=count(var_hint)->total(primary_fallback)"
    assert compare.surfaces.watch.key_target_changed == true
    assert compare.surfaces.watch.current_target_numeric_key == "count"
    assert compare.surfaces.watch.compare_target_numeric_key == "total"
    assert compare.surfaces.watch.current_active_target_key_source == "var_hint"
    assert compare.surfaces.watch.compare_active_target_key_source == "primary_fallback"
  end

  test "runtime_fingerprint_compare_at_cursor preserves explicit false values in sparse rows" do
    events = [
      %{
        seq: 3,
        type: "debugger.runtime_exec",
        payload: %{},
        watch: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("a", 64),
            "runtime_view_tree_sha256" => String.duplicate("b", 64),
            "elm_executor" => %{
              "active_target_key" => false,
              "active_target_key_source" => "field_hint"
            }
          }
        }
      },
      %{
        seq: 2,
        type: "debugger.runtime_exec",
        payload: %{},
        companion: %{
          model: %{
            "runtime_model_sha256" => String.duplicate("c", 64),
            "runtime_view_tree_sha256" => String.duplicate("d", 64)
          }
        }
      }
    ]

    compare = DebuggerSupport.runtime_fingerprint_compare_at_cursor(events, 3, 2)

    assert compare.changed_surface_count == 2
    assert compare.key_target_changed_surface_count == 1
    assert compare.surfaces.watch.key_target_changed == true
    assert compare.surfaces.watch.current_active_target_key == "false"
    assert compare.surfaces.watch.compare_active_target_key == nil
    assert compare.key_target_drift_detail =~ "watch=false(field_hint)->nil(nil)"
  end

  test "backend_drift_detail formats surface backend transitions and truncates long reasons" do
    compare = %{
      surfaces: %{
        watch: %{
          backend_changed: true,
          current_execution_backend: "external",
          compare_execution_backend: "default",
          current_external_fallback_reason:
            "{:external_runtime_executor_failed, {:very_long_reason, :that_should_be_truncated_for_ui}}",
          compare_external_fallback_reason: nil
        },
        companion: %{
          backend_changed: false,
          current_execution_backend: "default",
          compare_execution_backend: "default"
        }
      }
    }

    detail = DebuggerSupport.backend_drift_detail(compare, 36)
    assert is_binary(detail)
    assert detail =~ "watch=external->default"
    assert detail =~ "[reason"
    assert detail =~ "..."
    refute detail =~ "companion="
  end

  test "export_trace_opts uses cursor and explicit compare baseline anchors" do
    socket =
      DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})
      |> Phoenix.Component.assign(:debugger_cursor_seq, 42)
      |> Phoenix.Component.assign(:debugger_compare_baseline_seq, 30)

    opts = DebuggerSupport.export_trace_opts(socket)
    assert Keyword.get(opts, :event_limit) == 500
    assert Keyword.get(opts, :compare_cursor_seq) == 42
    assert Keyword.get(opts, :baseline_cursor_seq) == 30
  end

  test "export_trace_opts prefers explicit submit values and falls back on invalid input" do
    socket =
      DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})
      |> Phoenix.Component.assign(:debugger_cursor_seq, 42)
      |> Phoenix.Component.assign(:debugger_compare_baseline_seq, 30)

    explicit_opts =
      DebuggerSupport.export_trace_opts(socket, %{
        "compare_cursor_seq" => "9",
        "baseline_cursor_seq" => "2"
      })

    assert Keyword.get(explicit_opts, :compare_cursor_seq) == 9
    assert Keyword.get(explicit_opts, :baseline_cursor_seq) == 2

    fallback_opts =
      DebuggerSupport.export_trace_opts(socket, %{
        "compare_cursor_seq" => "bogus",
        "baseline_cursor_seq" => "-3"
      })

    assert Keyword.get(fallback_opts, :compare_cursor_seq) == 42
    assert Keyword.get(fallback_opts, :baseline_cursor_seq) == 30
  end

  test "set_compare_form updates explicit baseline cursor and allows clearing" do
    socket = DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})
    socket = DebuggerSupport.set_compare_form(socket, %{"baseline_seq" => "12"})
    assert socket.assigns.debugger_compare_baseline_seq == 12
    assert socket.assigns.debugger_compare_form[:baseline_seq].value == "12"

    socket = DebuggerSupport.set_compare_form(socket, %{"baseline_seq" => ""})
    assert socket.assigns.debugger_compare_baseline_seq == nil
    assert socket.assigns.debugger_compare_form[:baseline_seq].value == ""
  end

  test "use_preview_as_compare_baseline copies replay preview seq explicitly" do
    socket =
      DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})
      |> Phoenix.Component.assign(:debugger_replay_preview_seq, 27)
      |> DebuggerSupport.use_preview_as_compare_baseline()

    assert socket.assigns.debugger_compare_baseline_seq == 27
    assert socket.assigns.debugger_compare_form[:baseline_seq].value == "27"
  end

  test "set_export_form stores latest raw cursor inputs" do
    socket =
      DebuggerSupport.assign_defaults(%Phoenix.LiveView.Socket{})
      |> DebuggerSupport.set_export_form(%{
        "compare_cursor_seq" => "17",
        "baseline_cursor_seq" => ""
      })

    assert socket.assigns.debugger_export_form[:compare_cursor_seq].value == "17"
    assert socket.assigns.debugger_export_form[:baseline_cursor_seq].value == ""
  end

  test "diagnostics_preview_at_cursor falls back to watch model when payload empty" do
    events = [
      %{
        seq: 2,
        type: "debugger.reload",
        payload: %{},
        watch: %{model: %{"elmc_diagnostic_preview" => [%{"message" => "from model"}]}}
      }
    ]

    assert %{source: "cursor_model", rows: [%{"message" => "from model"}]} =
             DebuggerSupport.diagnostics_preview_at_cursor(events, 2)
  end

  test "update_messages_at_cursor lists update_in events through cursor" do
    events = [
      %{seq: 5, type: "debugger.update_in", payload: %{target: "watch", message: "A"}},
      %{seq: 3, type: "debugger.start", payload: %{}},
      %{seq: 4, type: "debugger.update_in", payload: %{target: "companion", message: "B"}}
    ]

    rows = DebuggerSupport.update_messages_at_cursor(events, 5, 10)
    assert Enum.map(rows, & &1.seq) == [4, 5]
    assert Enum.map(rows, & &1.target) == ["companion", "watch"]
  end

  test "render_events_at_cursor collects view_render rows in order" do
    events = [
      %{seq: 5, type: "debugger.view_render", payload: %{"target" => "watch", "root" => "a"}},
      %{seq: 2, type: "debugger.start", payload: %{}},
      %{seq: 4, type: "debugger.view_render", payload: %{"target" => "phone", "root" => "b"}}
    ]

    rows = DebuggerSupport.render_events_at_cursor(events, 5, 10)
    assert Enum.map(rows, & &1.seq) == [4, 5]
    assert Enum.map(rows, & &1.target) == ["phone", "watch"]
  end

  test "lifecycle_events_at_cursor includes elmc_manifest with summary" do
    events = [
      %{
        seq: 3,
        type: "debugger.elmc_manifest",
        payload: %{
          status: "ok",
          error_count: 0,
          strict: true,
          schema_version: "1",
          manifest_path: "/m"
        }
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    rows = DebuggerSupport.lifecycle_events_at_cursor(events, 3, 10)
    assert Enum.map(rows, & &1.type) == ["debugger.start", "debugger.elmc_manifest"]
    assert List.last(rows).summary =~ "strict=true"
    assert List.last(rows).summary =~ "schema 1"
  end

  test "lifecycle_events_at_cursor includes elmc_compile with summary" do
    events = [
      %{
        seq: 5,
        type: "debugger.elmc_compile",
        payload: %{
          status: "ok",
          error_count: 0,
          revision: "abc12",
          cached: true,
          compiled_path: "/c"
        }
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    rows = DebuggerSupport.lifecycle_events_at_cursor(events, 5, 10)
    assert Enum.map(rows, & &1.type) == ["debugger.start", "debugger.elmc_compile"]
    assert List.last(rows).summary =~ "abc12"
    assert List.last(rows).summary =~ "cached=true"
  end

  test "lifecycle_events_at_cursor includes elmc_check with summary" do
    events = [
      %{
        seq: 4,
        type: "debugger.elmc_check",
        payload: %{status: "ok", error_count: 0, warning_count: 1, checked_path: "/w"}
      },
      %{
        seq: 2,
        type: "debugger.reload",
        payload: %{"rel_path" => "src/M.elm", "revision" => "r"}
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    rows = DebuggerSupport.lifecycle_events_at_cursor(events, 4, 10)

    assert Enum.map(rows, & &1.type) == [
             "debugger.start",
             "debugger.reload",
             "debugger.elmc_check"
           ]

    assert List.last(rows).summary =~ "ok"
    assert List.last(rows).summary =~ "1 warn"
    assert List.last(rows).summary =~ "/w"
  end

  test "lifecycle_events_at_cursor summarizes reload payload" do
    events = [
      %{
        seq: 3,
        type: "debugger.reload",
        payload: %{
          "source_root" => "phone",
          "rel_path" => "src/M.elm",
          "revision" => "abc"
        }
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    rows = DebuggerSupport.lifecycle_events_at_cursor(events, 3, 10)
    assert Enum.map(rows, & &1.type) == ["debugger.start", "debugger.reload"]
    assert List.last(rows).summary =~ "phone"
    assert List.last(rows).summary =~ "src/M.elm"
  end

  test "lifecycle_events_at_cursor summarizes debugger.elm_introspect payload" do
    events = [
      %{
        seq: 2,
        type: "debugger.elm_introspect",
        payload: %{
          module: "M",
          target: "companion",
          msg_count: 2,
          update_branch_count: 3,
          update_case_subject: "msg",
          init_case_branch_count: 2,
          init_case_subject: "flags",
          view_branch_count: 2,
          view_case_subject: "model",
          subscriptions_case_branch_count: 2,
          subscriptions_case_subject: "model.page",
          subscription_count: 2,
          view_root: "root",
          main_kind: "worker",
          init_cmd_count: 2,
          init_cmd_preview: "Cmd.none, Cmd.none",
          update_cmd_count: 1,
          update_cmd_preview: "Http.get",
          port_count: 2,
          ports_preview: "toJs, fromJs",
          import_count: 3,
          imports_preview: "Html, Platform, Json",
          import_entry_count: 2,
          import_entries_preview: "Html; Json.Decode as Decode (..)",
          type_alias_count: 1,
          type_aliases_preview: "Model",
          union_type_count: 2,
          union_types_preview: "Msg, Page",
          top_level_function_count: 5,
          top_level_functions_preview: "init, update, view, subscriptions, main",
          port_module: true,
          module_exposing: "..",
          module_exposing_preview: "(..)"
        }
      },
      %{seq: 1, type: "debugger.start", payload: %{}}
    ]

    rows = DebuggerSupport.lifecycle_events_at_cursor(events, 2, 10)
    intro = Enum.find(rows, &(&1.type == "debugger.elm_introspect"))
    assert intro.summary =~ "M"
    assert intro.summary =~ "companion"
    assert intro.summary =~ "2 msgs"
    assert intro.summary =~ "view root"
    assert intro.summary =~ "3 update branches"
    assert intro.summary =~ "2 subs"
    assert intro.summary =~ "main worker"
    assert intro.summary =~ "2 init cmds"
    assert intro.summary =~ "1 update cmds"
    assert intro.summary =~ "case msg"
    assert intro.summary =~ "2 view case branches"
    assert intro.summary =~ "2 init case branches"
    assert intro.summary =~ "2 subscriptions case branches"
    assert intro.summary =~ "init case flags"
    assert intro.summary =~ "subs case model.page"
    assert intro.summary =~ "view case model"
    assert intro.summary =~ "2 ports"
    assert intro.summary =~ "3 imports"
    assert intro.summary =~ "2 import lines"
    assert intro.summary =~ "1 type aliases"
    assert intro.summary =~ "2 unions"
    assert intro.summary =~ "5 functions"
    assert intro.summary =~ "port module"
    assert intro.summary =~ "exposing (..)"
  end

  test "protocol_exchange_at_cursor filters by seq and orders chronologically" do
    events = [
      %{seq: 4, type: "debugger.protocol_tx", payload: %{from: "w", to: "c", message: "a"}},
      %{seq: 2, type: "debugger.start", payload: %{}},
      %{seq: 3, type: "debugger.protocol_rx", payload: %{from: "w", to: "c", message: "b"}}
    ]

    rows = DebuggerSupport.protocol_exchange_at_cursor(events, 4, 10)
    assert Enum.map(rows, & &1.seq) == [3, 4]
    assert Enum.map(rows, & &1.kind) == ["rx", "tx"]
  end

  defp assert_replay_telemetry(actual, expected) when is_map(actual) and is_map(expected) do
    assert actual.mode == expected.mode
    assert actual.source == expected.source
    assert actual.drift_seq == expected.drift_seq
    assert actual.drift_band == expected.drift_band
    assert actual.used_live_query == expected.used_live_query
    assert actual.used_frozen_preview == expected.used_frozen_preview
  end

  defp debugger_trace_body(slug, debugger_timeline) do
    %{
      "export_version" => 1,
      "project_slug" => slug,
      "running" => true,
      "revision" => nil,
      "watch_profile_id" => "basalt",
      "launch_context" => %{},
      "watch" => %{"model" => %{}, "view_tree" => %{"type" => "root", "children" => []}},
      "companion" => %{"model" => %{}, "view_tree" => %{"type" => "CompanionRoot"}},
      "phone" => %{"model" => %{}, "view_tree" => %{"type" => "PhoneRoot"}},
      "events" => [],
      "seq" => 0,
      "debugger_seq" => debugger_timeline |> Enum.map(& &1["seq"]) |> Enum.max(fn -> 0 end),
      "debugger_timeline" => debugger_timeline
    }
  end

  defp debugger_row(seq, value) do
    %{
      "seq" => seq,
      "raw_seq" => seq * 10,
      "type" => "update",
      "target" => "watch",
      "message" => "Tick #{value}",
      "message_source" => "subscription_auto_fire",
      "watch" => %{
        "model" => %{"runtime_model" => %{"value" => value}},
        "view_tree" => %{"type" => "root", "children" => []}
      },
      "companion" => %{"model" => %{}, "view_tree" => %{"type" => "CompanionRoot"}},
      "phone" => %{"model" => %{}, "view_tree" => %{"type" => "PhoneRoot"}}
    }
  end
end
