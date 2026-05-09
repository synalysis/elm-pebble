defmodule Ide.Mcp.Tools do
  @moduledoc """
  Capability-scoped MCP tool registry and dispatcher for IDE operations.
  """

  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Compiler.Cache, as: CompileCache
  alias Ide.Compiler.ManifestCache
  alias Ide.Mcp.Audit
  alias Ide.Mcp.CheckCache
  alias Ide.Packages
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Debugger
  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @type capability :: :read | :edit | :build | :publish
  @type tool_result :: {:ok, map()} | {:error, String.t()}
  @type maybe_since :: DateTime.t() | nil
  @type maybe_slug :: String.t() | nil
  @type maybe_trace_id :: String.t() | nil
  @tool_version "1.0.0"
  @catalog_version "2026-05-23"

  @read_tools [
    %{
      name: "projects.list",
      description: "List known IDE projects.",
      inputSchema: %{type: "object", additionalProperties: false, properties: %{}}
    },
    %{
      name: "projects.tree",
      description: "List source tree grouped by roots for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string", description: "Project slug."}
        }
      }
    },
    %{
      name: "files.read",
      description: "Read a source file from a project root.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "source_root", "rel_path"],
        properties: %{
          slug: %{type: "string"},
          source_root: %{type: "string"},
          rel_path: %{type: "string"}
        }
      }
    },
    %{
      name: "packages.search",
      description: "Search Elm package catalog entries.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          query: %{type: "string"},
          page: %{type: "integer", minimum: 1, maximum: 500},
          per_page: %{type: "integer", minimum: 1, maximum: 200},
          platform_target: %{
            type: "string",
            enum: ["watch", "phone"],
            description: "Optional catalog compatibility target."
          }
        }
      }
    },
    %{
      name: "packages.details",
      description: "Read package details and versions from catalog.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["package"],
        properties: %{
          package: %{type: "string"}
        }
      }
    },
    %{
      name: "packages.versions",
      description: "Read all known versions for a package.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["package"],
        properties: %{
          package: %{type: "string"}
        }
      }
    },
    %{
      name: "packages.readme",
      description: "Read package README markdown for selected package/version.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["package"],
        properties: %{
          package: %{type: "string"},
          version: %{type: "string", description: "Version string; defaults to latest."}
        }
      }
    },
    %{
      name: "projects.graph",
      description: "Return project context graph with workspace and file counts.",
      inputSchema: %{type: "object", additionalProperties: false, properties: %{}}
    },
    %{
      name: "audit.recent",
      description: "Read recent MCP action traces.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "compiler.check_cached",
      description: "Read most recent cached compiler check result for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "compiler.check_recent",
      description: "Read recent compiler check history from cache.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for check timestamp."}
        }
      }
    },
    %{
      name: "compiler.compile_cached",
      description: "Read most recent cached compiler compile result for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "compiler.compile_recent",
      description: "Read recent compiler compile history from cache.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for compile timestamp."}
        }
      }
    },
    %{
      name: "compiler.manifest_cached",
      description: "Read most recent cached compiler manifest result for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "compiler.manifest_recent",
      description: "Read recent compiler manifest history from cache.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for manifest timestamp."}
        }
      }
    },
    %{
      name: "sessions.recent_activity",
      description: "Summarize recent project activity for AI context.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "sessions.summary",
      description: "Return compact per-project status summaries for AI prompts.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          slug: %{type: "string"},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "sessions.trace_health",
      description: "Report trace export storage health and cleanup recommendations.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          warn_count: %{type: "integer", minimum: 1, maximum: 100_000},
          warn_bytes: %{type: "integer", minimum: 1}
        }
      }
    },
    %{
      name: "traces.bundle",
      description: "Return correlated audit + compiler context for reproducible trace workflows.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          trace_id: %{type: "string"},
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "traces.summary",
      description: "Return compact trace summary for prompt-budget sensitive workflows.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          trace_id: %{type: "string"},
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "traces.export",
      description: "Return deterministic JSON trace export payload and checksum.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          trace_id: %{type: "string"},
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "traces.exports_list",
      description: "List persisted trace export artifacts from disk.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          limit: %{type: "integer", minimum: 1, maximum: 200}
        }
      }
    },
    %{
      name: "traces.policy",
      description: "Read effective trace retention policy defaults.",
      inputSchema: %{type: "object", additionalProperties: false, properties: %{}}
    },
    %{
      name: "traces.policy_validate",
      description: "Validate effective trace retention policy and return safety findings.",
      inputSchema: %{type: "object", additionalProperties: false, properties: %{}}
    },
    %{
      name: "debugger.state",
      description:
        "Read debugger runtime state snapshot for a project. Set replay_metadata_only=true for lightweight polling.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          event_limit: %{type: "integer", minimum: 1, maximum: 500},
          since_seq: %{type: "integer", minimum: 0},
          compare_cursor_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional cursor seq baseline for runtime_fingerprint_compare drift checks."
          },
          include_replay_metadata: %{
            type: "boolean",
            description: "If false, skip replay metadata extraction for lower-overhead polling."
          },
          replay_metadata_only: %{
            type: "boolean",
            description:
              "If true, return only replay metadata + event_window without full state payload."
          },
          types: %{
            type: "array",
            items: %{type: "string"},
            description: "Optional event type filter list."
          }
        }
      }
    },
    %{
      name: "debugger.export_trace",
      description:
        "Export deterministic JSON trace of debugger events and runtime snapshots for replay and bug reports.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          event_limit: %{type: "integer", minimum: 1, maximum: 500},
          compare_cursor_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional cursor seq to anchor runtime_fingerprint_compare.current_cursor_seq in export payload."
          },
          baseline_cursor_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional cursor seq baseline for runtime_fingerprint_compare.baseline_cursor_seq in export payload."
          }
        }
      }
    },
    %{
      name: "debugger.cursor_inspect",
      description:
        "Read debugger table rows (update messages, protocol exchange, view renders, lifecycle) scoped to a timeline cursor, matching the Debugger tab. Lifecycle includes debugger.elm_introspect when a non-trivial parser snapshot was merged on reload. Also returns elmc_diagnostics (capped preview rows), elmc_diagnostics_source (event_payload | cursor_model | cursor_model_companion | cursor_model_phone | none), and elm_introspect (watch | companion | phone parser snapshots: imported_modules (explicit imports only), source_byte_size and source_line_count (raw file), import_entries/module_exposing/ports/port_module from parser-derived `elmc` header metadata (see `ElmEx.Frontend.GeneratedParser` contract), type_aliases, unions (custom type names), functions (top-level definitions), init_model (tuple peel, or first init case-branch model when branches return ( model, Cmd )), init_cmd_ops (peeled init tuple Cmd side, or the same Cmd outline from each branch of a recognized top-level init case on init parameters / param.field), init_case_branches and init_case_subject (same recognition rules as init_cmd_ops case), init_params, msg_constructors, update_params, update_cmd_ops (top-level ( model, Cmd ) tuple, or the same Cmd outline from each branch of a recognized top-level case on msg / parameters / param.field), update_case_branches and update_case_subject (top-level case on msg, message, any update parameter, or param.field chains), view_case_branches and view_case_subject (top-level view case on model, the first view parameter, or param.field chains), subscription_ops (top-level Sub/Cmd batch outline, or merged from each branch of a recognized top-level case on subscriptions parameters / param.field), subscriptions_case_branches and subscriptions_case_subject (same recognition rules as subscription_ops case), subscriptions_params, view_params, main_program when present, view_tree when present). Loads the newest events up to event_limit (default 500). Omit cursor_seq to use the latest seq in that window.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          cursor_seq: %{type: "integer", minimum: 0},
          compare_cursor_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional baseline cursor seq for runtime_fingerprint_compare against the selected cursor."
          },
          event_limit: %{type: "integer", minimum: 1, maximum: 500},
          replay_metadata_only: %{
            type: "boolean",
            description:
              "If true, return only cursor/event window/replay metadata without diagnostics/tables."
          },
          include_replay_metadata: %{
            type: "boolean",
            description:
              "If false, skip replay metadata extraction for lower-overhead inspect calls."
          },
          update_limit: %{type: "integer", minimum: 1, maximum: 100},
          protocol_limit: %{type: "integer", minimum: 1, maximum: 100},
          render_limit: %{type: "integer", minimum: 1, maximum: 100},
          lifecycle_limit: %{type: "integer", minimum: 1, maximum: 100}
        }
      }
    }
  ]

  @edit_tools [
    %{
      name: "projects.create",
      description: "Create a new IDE project and bootstrap source roots.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["name", "slug"],
        properties: %{
          name: %{type: "string"},
          slug: %{type: "string"},
          target_type: %{type: "string", enum: ["app", "watchface", "companion"]},
          template: %{
            type: "string",
            enum: [
              "starter",
              "watchface-digital",
              "watchface-analog",
              "watchface-tutorial-complete",
              "game-basic",
              "game-tiny-bird",
              "game-greeneys-run",
              "game-2048"
            ]
          }
        }
      }
    },
    %{
      name: "projects.delete",
      description: "Delete an IDE project and remove its local workspace.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "files.write",
      description: "Write a source file in a project root.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "source_root", "rel_path", "content"],
        properties: %{
          slug: %{type: "string"},
          source_root: %{type: "string"},
          rel_path: %{type: "string"},
          content: %{type: "string"}
        }
      }
    },
    %{
      name: "packages.add_to_elm_json",
      description:
        "Add package dependency to project elm.json using compatible version auto-resolution.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "package"],
        properties: %{
          slug: %{type: "string"},
          package: %{type: "string"},
          source_root: %{type: "string", description: "Optional source root containing elm.json."},
          section: %{
            type: "string",
            enum: ["dependencies", "test-dependencies"],
            description: "Dependency section (default: dependencies)."
          },
          scope: %{
            type: "string",
            enum: ["direct", "indirect"],
            description: "Dependency scope (default: direct)."
          }
        }
      }
    },
    %{
      name: "packages.remove_from_elm_json",
      description:
        "Remove a direct package dependency from elm.json and re-resolve indirect dependencies. Built-in Pebble packages cannot be removed.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "package"],
        properties: %{
          slug: %{type: "string"},
          package: %{type: "string"},
          source_root: %{type: "string", description: "Optional source root containing elm.json."},
          section: %{
            type: "string",
            enum: ["dependencies", "test-dependencies"],
            description: "Dependency section (default: dependencies)."
          }
        }
      }
    },
    %{
      name: "traces.export_write",
      description: "Write deterministic trace export JSON to disk.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          trace_id: %{type: "string"},
          slug: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200},
          since: %{type: "string", description: "ISO8601 lower bound for activity timestamp."}
        }
      }
    },
    %{
      name: "traces.exports_prune",
      description: "Delete older trace exports, keeping the most recent N.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          keep_latest: %{type: "integer", minimum: 0, maximum: 2000}
        }
      }
    },
    %{
      name: "traces.maintenance",
      description: "Evaluate trace health and optionally prune in one guarded operation.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          warn_count: %{type: "integer", minimum: 1, maximum: 100_000},
          warn_bytes: %{type: "integer", minimum: 1},
          target_keep_latest: %{type: "integer", minimum: 0, maximum: 2000},
          apply: %{type: "boolean"}
        }
      }
    },
    %{
      name: "debugger.start",
      description: "Start debugger runtime session for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "debugger.reset",
      description: "Reset debugger runtime state for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "debugger.reload",
      description:
        "Simulate IDE hot reload after a file change (revision bump, update_in, protocol, view renders). Matches save-hook behavior.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "rel_path"],
        properties: %{
          slug: %{type: "string"},
          rel_path: %{type: "string"},
          source: %{type: "string", description: "Optional source text for revision hash."},
          reason: %{type: "string", description: "Optional label on the reload event."},
          source_root: %{
            type: "string",
            description:
              "watch | protocol | phone — drives which surface leads the hot-reload simulation.",
            enum: ["watch", "protocol", "phone"]
          }
        }
      }
    },
    %{
      name: "debugger.step",
      description:
        "Apply deterministic debugger step events for a target runtime (watch/companion/phone) to advance debugger state.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{type: "string", enum: ["watch", "companion", "protocol", "phone"]},
          message: %{type: "string", description: "Synthetic message label for the step event."},
          count: %{type: "integer", minimum: 1, maximum: 50}
        }
      }
    },
    %{
      name: "debugger.tick",
      description:
        "Inject deterministic subscription-style tick messages into debugger runtimes (single target or all surfaces).",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{type: "string", enum: ["watch", "companion", "protocol", "phone"]},
          count: %{type: "integer", minimum: 1, maximum: 50}
        }
      }
    },
    %{
      name: "debugger.auto_tick_start",
      description:
        "Start fixed-interval deterministic tick ingress into debugger runtimes until stopped.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{type: "string", enum: ["watch", "companion", "protocol", "phone"]},
          count: %{type: "integer", minimum: 1, maximum: 50},
          interval_ms: %{type: "integer", minimum: 100, maximum: 60000}
        }
      }
    },
    %{
      name: "debugger.auto_tick_stop",
      description: "Stop fixed-interval deterministic tick ingress.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "debugger.replay_recent",
      description:
        "Replay recent debugger update messages back into runtime state (deterministic oldest-to-newest application within the selected window).",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{type: "string", enum: ["watch", "companion", "protocol", "phone"]},
          count: %{type: "integer", minimum: 1, maximum: 50},
          replay_mode: %{
            type: "string",
            enum: ["frozen", "live"],
            description: "Optional telemetry hint for replay intent (frozen vs live query)."
          },
          replay_drift_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional positive drift distance (latest_seq - preview_baseline_seq) recorded into replay telemetry."
          },
          cursor_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional upper timeline bound; only update_in events at or before this seq are replayed."
          }
        }
      }
    },
    %{
      name: "debugger.continue_from_snapshot",
      description:
        "Materialize a selected timeline snapshot into live debugger tip state, then continue stepping/ticking from that snapshot.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          cursor_seq: %{
            type: "integer",
            minimum: 0,
            description:
              "Optional timeline cursor seq to materialize; defaults to latest in-window."
          }
        }
      }
    },
    %{
      name: "debugger.import_trace",
      description:
        "Replace debugger state with a deterministic JSON trace export (replay). project_slug in JSON must match slug unless strict_slug is false.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "export_json"],
        properties: %{
          slug: %{type: "string"},
          export_json: %{type: "string", description: "JSON from debugger.export_trace"},
          strict_slug: %{type: "boolean", description: "If false, allow project_slug mismatch."},
          expected_sha256: %{
            type: "string",
            description:
              "Optional deterministic guard. If provided, import only succeeds when export_json SHA-256 matches this value."
          }
        }
      }
    }
  ]

  @build_tools [
    %{
      name: "pebble.package",
      description: "Build a project-specific .pbw artifact for emulator/install workflows.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "pebble.install",
      description:
        "Install a .pbw artifact to a Pebble emulator target. If package_path is omitted, package is generated first.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          package_path: %{type: "string"},
          emulator_target: %{type: "string"},
          logs_snapshot_seconds: %{type: "integer", minimum: 1, maximum: 30}
        }
      }
    },
    %{
      name: "screenshots.capture",
      description: "Capture a screenshot from the selected emulator target.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          emulator_target: %{type: "string"}
        }
      }
    },
    %{
      name: "compiler.check",
      description: "Run elmc check for a project and return diagnostics.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "compiler.compile",
      description: "Run elmc compile for a project and return diagnostics.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "compiler.manifest",
      description: "Run elmc manifest for a project and return manifest JSON + diagnostics.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          strict: %{
            type: "boolean",
            description: "If true, validation warnings turn manifest status into error."
          }
        }
      }
    }
  ]

  @publish_tools []

  @spec tool_definitions([capability()]) :: [map()]
  def tool_definitions(capabilities) do
    []
    |> add_if(:read in capabilities, @read_tools)
    |> add_if(:edit in capabilities, @edit_tools)
    |> add_if(:build in capabilities, @build_tools)
    |> add_if(:publish in capabilities, @publish_tools)
    |> Enum.map(&Map.put_new(&1, :version, @tool_version))
  end

  @spec catalog_version() :: String.t()
  def catalog_version, do: @catalog_version

  @spec call(String.t(), map(), [capability()]) :: {:ok, map()} | {:error, String.t()}
  def call(name, args, capabilities) when is_binary(name) and is_map(args) do
    if authorized?(name, capabilities) do
      do_call(name, args)
    else
      {:error, "tool not permitted by current capability scope"}
    end
  end

  @spec audit_arguments(String.t(), map()) :: map()
  def audit_arguments("files.write", %{"content" => content} = args) when is_binary(content) do
    args
    |> Map.drop(["content"])
    |> Map.put("content_redacted", true)
    |> Map.put("content_bytes", byte_size(content))
  end

  def audit_arguments("debugger.import_trace", %{"export_json" => json} = args)
      when is_binary(json) do
    args
    |> Map.drop(["export_json"])
    |> Map.put("export_json_redacted", true)
    |> Map.put("export_json_bytes", byte_size(json))
  end

  def audit_arguments("debugger.reload", %{"source" => source} = args) when is_binary(source) do
    args
    |> Map.drop(["source"])
    |> Map.put("source_redacted", true)
    |> Map.put("source_bytes", byte_size(source))
  end

  def audit_arguments(_name, args) when is_map(args), do: args

  @spec do_call(String.t(), map()) :: tool_result()
  defp do_call("projects.list", _args) do
    projects =
      Projects.list_projects()
      |> Enum.map(fn project ->
        %{
          name: project.name,
          slug: project.slug,
          target_type: project.target_type,
          source_roots: project.source_roots,
          active: project.active
        }
      end)

    {:ok, %{projects: projects}}
  end

  defp do_call("projects.tree", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug) do
      {:ok, %{slug: slug, tree: Projects.list_source_tree(project)}}
    end
  end

  defp do_call("projects.graph", _args) do
    projects =
      Projects.list_projects()
      |> Enum.map(fn project ->
        workspace = Projects.project_workspace_path(project)
        tree = Projects.list_source_tree(project)

        %{
          name: project.name,
          slug: project.slug,
          target_type: project.target_type,
          active: project.active,
          source_roots: project.source_roots,
          workspace_path: workspace,
          file_count: count_files(tree)
        }
      end)

    {:ok, %{projects: projects}}
  end

  defp do_call("projects.create", %{"name" => name, "slug" => slug} = args) do
    attrs =
      %{
        "name" => name,
        "slug" => slug
      }
      |> put_opt_map("target_type", Map.get(args, "target_type"))
      |> put_opt_map("template", Map.get(args, "template"))

    case Projects.create_project(attrs) do
      {:ok, project} ->
        {:ok,
         %{
           name: project.name,
           slug: project.slug,
           target_type: project.target_type,
           source_roots: project.source_roots,
           active: project.active
         }}

      {:error, reason} ->
        {:error, "project create failed: #{inspect(reason)}"}
    end
  end

  defp do_call("projects.delete", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, _deleted} <- Projects.delete_project(project) do
      {:ok, %{slug: slug, deleted: true}}
    else
      {:error, reason} -> {:error, "project delete failed: #{inspect(reason)}"}
    end
  end

  defp do_call("files.read", %{
         "slug" => slug,
         "source_root" => source_root,
         "rel_path" => rel_path
       }) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, content} <- Projects.read_source_file(project, source_root, rel_path) do
      {:ok, %{slug: slug, source_root: source_root, rel_path: rel_path, content: content}}
    else
      {:error, reason} -> {:error, "read failed: #{inspect(reason)}"}
    end
  end

  defp do_call("packages.search", args) do
    query = Map.get(args, "query", "")
    platform_target = parse_platform_target(Map.get(args, "platform_target"))

    opts =
      []
      |> put_opt(:page, Map.get(args, "page"))
      |> put_opt(:per_page, Map.get(args, "per_page"))
      |> put_opt(:platform_target, platform_target)

    case Packages.search(query, opts) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages search failed: #{inspect(reason)}"}
    end
  end

  defp do_call("packages.details", %{"package" => package}) do
    case Packages.package_details(package, []) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages details failed: #{inspect(reason)}"}
    end
  end

  defp do_call("packages.versions", %{"package" => package}) do
    case Packages.versions(package, []) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages versions failed: #{inspect(reason)}"}
    end
  end

  defp do_call("packages.readme", %{"package" => package} = args) do
    version = Map.get(args, "version", "latest")

    case Packages.readme(package, version, []) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages readme failed: #{inspect(reason)}"}
    end
  end

  defp do_call(
         "files.write",
         %{
           "slug" => slug,
           "source_root" => source_root,
           "rel_path" => rel_path,
           "content" => content
         }
       ) do
    with {:ok, project} <- fetch_project(slug),
         :ok <- Projects.write_source_file(project, source_root, rel_path, content) do
      {:ok, %{saved: true, slug: slug, source_root: source_root, rel_path: rel_path}}
    else
      {:error, reason} -> {:error, "write failed: #{inspect(reason)}"}
    end
  end

  defp do_call("packages.add_to_elm_json", %{"slug" => slug, "package" => package} = args) do
    opts =
      []
      |> put_opt(:source_root, Map.get(args, "source_root"))
      |> put_opt(:section, Map.get(args, "section"))
      |> put_opt(:scope, Map.get(args, "scope"))

    with {:ok, project} <- fetch_project(slug),
         {:ok, result} <- Packages.add_to_project(project, package, opts) do
      {:ok, Map.put(result, :slug, slug)}
    else
      {:error, reason} -> {:error, "packages add failed: #{inspect(reason)}"}
    end
  end

  defp do_call("packages.remove_from_elm_json", %{"slug" => slug, "package" => package} = args) do
    opts =
      []
      |> put_opt(:source_root, Map.get(args, "source_root"))
      |> put_opt(:section, Map.get(args, "section"))

    with {:ok, project} <- fetch_project(slug),
         {:ok, result} <- Packages.remove_from_project(project, package, opts) do
      {:ok, Map.put(result, :slug, slug)}
    else
      {:error, reason} -> {:error, "packages remove failed: #{inspect(reason)}"}
    end
  end

  defp do_call("compiler.check", %{"slug" => slug}) do
    compiler = compiler_module()

    with {:ok, project} <- fetch_project(slug),
         {:ok, result} <-
           compiler.check(slug, workspace_root: Projects.project_workspace_path(project)) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)
      :ok = CheckCache.put(slug, result)

      {:ok,
       %{
         slug: slug,
         status: result.status,
         checked_path: result.checked_path,
         diagnostics: diagnostics,
         error_count: counts.error_count,
         warning_count: counts.warning_count,
         output: result.output
       }}
    else
      {:error, reason} -> {:error, "check failed: #{inspect(reason)}"}
    end
  end

  defp do_call("pebble.package", %{"slug" => slug}) do
    toolchain = pebble_toolchain_module()

    with {:ok, project} <- fetch_project(slug),
         {:ok, result} <-
           toolchain.package(slug,
             workspace_root: Projects.project_workspace_path(project),
             target_type: project.target_type,
             project_name: project.name
           ) do
      {:ok,
       %{
         slug: slug,
         status: result.status,
         artifact_path: result.artifact_path,
         app_root: result.app_root,
         build_result: result.build_result
       }}
    else
      {:error, reason} -> {:error, "pebble package failed: #{inspect(reason)}"}
    end
  end

  defp do_call("pebble.install", %{"slug" => slug} = args) do
    toolchain = pebble_toolchain_module()
    logs_snapshot_seconds = parse_logs_snapshot_seconds(Map.get(args, "logs_snapshot_seconds"))

    with {:ok, project} <- fetch_project(slug),
         {:ok, package_path} <- resolve_install_package_path(project, args, toolchain),
         {:ok, install_result} <-
           toolchain.run_emulator(slug,
             emulator_target: Map.get(args, "emulator_target"),
             package_path: package_path,
             logs_snapshot_seconds: logs_snapshot_seconds
           ) do
      {:ok, %{slug: slug, artifact_path: package_path, install_result: install_result}}
    else
      {:error, reason} -> {:error, "pebble install failed: #{inspect(reason)}"}
    end
  end

  defp do_call("screenshots.capture", %{"slug" => slug} = args) do
    screenshots = screenshots_module()

    with {:ok, _project} <- fetch_project(slug),
         {:ok, result} <-
           screenshots.capture(
             slug,
             emulator_target: Map.get(args, "emulator_target")
           ) do
      {:ok,
       %{
         slug: slug,
         screenshot: result.screenshot,
         output: result.output,
         exit_code: result.exit_code,
         command: result.command,
         cwd: result.cwd
       }}
    else
      {:error, reason} -> {:error, "screenshot capture failed: #{inspect(reason)}"}
    end
  end

  defp do_call("compiler.compile", %{"slug" => slug}) do
    compiler = compiler_module()

    with {:ok, project} <- fetch_project(slug),
         {:ok, result} <-
           compiler.compile(slug, workspace_root: Projects.project_workspace_path(project)) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)

      {:ok,
       %{
         slug: slug,
         status: result.status,
         compiled_path: result.compiled_path,
         revision: result.revision,
         cached: result.cached?,
         diagnostics: diagnostics,
         error_count: counts.error_count,
         warning_count: counts.warning_count,
         output: result.output
       }}
    else
      {:error, reason} -> {:error, "compile failed: #{inspect(reason)}"}
    end
  end

  defp do_call("compiler.manifest", %{"slug" => slug, "strict" => strict}) do
    strict? = strict == true
    compiler = compiler_module()

    with {:ok, project} <- fetch_project(slug),
         {:ok, result} <-
           compiler.manifest(slug,
             workspace_root: Projects.project_workspace_path(project),
             strict: strict?
           ) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)

      {:ok,
       %{
         slug: slug,
         status: result.status,
         manifest_path: result.manifest_path,
         revision: result.revision,
         cached: result.cached?,
         strict: result.strict?,
         manifest: result.manifest,
         diagnostics: diagnostics,
         error_count: counts.error_count,
         warning_count: counts.warning_count,
         output: result.output
       }}
    else
      {:error, reason} -> {:error, "manifest failed: #{inspect(reason)}"}
    end
  end

  defp do_call("compiler.manifest", %{"slug" => slug}) do
    do_call("compiler.manifest", %{"slug" => slug, "strict" => false})
  end

  defp do_call("compiler.compile_cached", %{"slug" => slug}) do
    case CompileCache.latest(slug) do
      {:ok, entry} ->
        {:ok,
         %{
           slug: slug,
           cached: true,
           at: entry.at,
           revision: entry.revision,
           result: entry.result
         }}

      {:error, :not_found} ->
        {:error, "no cached compile result for #{slug}"}
    end
  end

  defp do_call("compiler.compile_recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> parse_limit()

    with {:ok, since} <- parse_since(Map.get(args, "since")) do
      slug = Map.get(args, "slug")
      entries = CompileCache.recent(limit, slug) |> filter_since(since)
      {:ok, %{entries: entries, limit: limit, slug: slug, since: format_since(since)}}
    end
  end

  defp do_call("compiler.manifest_cached", %{"slug" => slug}) do
    case ManifestCache.latest(slug) do
      {:ok, entry} ->
        {:ok,
         %{
           slug: slug,
           cached: true,
           at: entry.at,
           revision: entry.revision,
           result: entry.result
         }}

      {:error, :not_found} ->
        {:error, "no cached manifest result for #{slug}"}
    end
  end

  defp do_call("compiler.manifest_recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> parse_limit()

    with {:ok, since} <- parse_since(Map.get(args, "since")) do
      slug = Map.get(args, "slug")
      entries = ManifestCache.recent(limit, slug) |> filter_since(since)
      {:ok, %{entries: entries, limit: limit, slug: slug, since: format_since(since)}}
    end
  end

  defp do_call("compiler.check_cached", %{"slug" => slug}) do
    case CheckCache.latest(slug) do
      {:ok, entry} ->
        {:ok, %{slug: slug, cached: true, at: entry.at, result: entry.result}}

      {:error, :not_found} ->
        {:error, "no cached check result for #{slug}"}
    end
  end

  defp do_call("compiler.check_recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> parse_limit()

    with {:ok, since} <- parse_since(Map.get(args, "since")) do
      slug = Map.get(args, "slug")
      entries = CheckCache.recent(limit, slug) |> filter_since(since)
      {:ok, %{entries: entries, limit: limit, slug: slug, since: format_since(since)}}
    end
  end

  defp do_call("audit.recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> parse_limit()

    with {:ok, since} <- parse_since(Map.get(args, "since")) do
      entries = Audit.recent(limit) |> filter_since(since)
      {:ok, %{entries: entries, limit: limit, since: format_since(since)}}
    end
  end

  defp do_call("traces.bundle", args) do
    with {:ok, bundle} <- build_trace_bundle(args) do
      {:ok, bundle}
    end
  end

  defp do_call("traces.summary", args) do
    with {:ok, bundle} <- build_trace_bundle(args) do
      checks = bundle.compiler_context.recent.checks
      compiles = bundle.compiler_context.recent.compiles
      manifests = bundle.compiler_context.recent.manifests
      actions = bundle.audit_entries

      {:ok,
       %{
         trace_id: bundle.trace_id,
         slug: bundle.slug,
         since: bundle.since,
         window: %{
           limit: bundle.limit,
           audit_entries: length(actions),
           checks: length(checks),
           compiles: length(compiles),
           manifests: length(manifests)
         },
         latest_status: %{
           check: status_of_entry(bundle.compiler_context.latest.check),
           compile: status_of_entry(bundle.compiler_context.latest.compile),
           manifest: status_of_entry(bundle.compiler_context.latest.manifest),
           manifest_strict: strict_of_entry(bundle.compiler_context.latest.manifest)
         },
         actions: action_counts(actions)
       }}
    end
  end

  defp do_call("traces.export", args) do
    with {:ok, bundle} <- build_trace_bundle(args) do
      payload = %{export_version: 1, trace_bundle: bundle}
      export_json = encode_canonical_json(payload)

      export_sha256 =
        :crypto.hash(:sha256, export_json)
        |> Base.encode16(case: :lower)

      {:ok,
       %{
         trace_id: bundle.trace_id,
         slug: bundle.slug,
         since: bundle.since,
         limit: bundle.limit,
         export_sha256: export_sha256,
         export_json: export_json
       }}
    end
  end

  defp do_call("traces.exports_list", args) do
    limit =
      args
      |> Map.get("limit", 50)
      |> parse_limit()

    with {:ok, files} <- read_trace_export_files() do
      entries =
        files
        |> Enum.take(limit)
        |> Enum.map(fn file ->
          %{
            file_name: file.file_name,
            path: file.path,
            bytes: file.bytes,
            modified_at: file.modified_at
          }
        end)

      {:ok, %{entries: entries, limit: limit, total_available: length(files)}}
    else
      {:error, reason} -> {:error, "trace exports list failed: #{inspect(reason)}"}
    end
  end

  defp do_call("traces.policy", _args) do
    configured_policy = trace_policy()

    {:ok,
     %{
       configured: %{
         warn_count: Keyword.get(configured_policy, :warn_count),
         warn_bytes: Keyword.get(configured_policy, :warn_bytes),
         keep_latest: Keyword.get(configured_policy, :keep_latest),
         target_keep_latest: Keyword.get(configured_policy, :target_keep_latest)
       },
       effective: %{
         warn_count: default_warn_count(),
         warn_bytes: default_warn_bytes(),
         keep_latest: default_keep_latest(),
         target_keep_latest: default_target_keep_latest()
       }
     }}
  end

  defp do_call("traces.policy_validate", _args) do
    effective = %{
      warn_count: default_warn_count(),
      warn_bytes: default_warn_bytes(),
      keep_latest: default_keep_latest(),
      target_keep_latest: default_target_keep_latest()
    }

    validation = policy_validation_payload(effective)
    {:ok, %{status: validation.status, policy: effective, findings: validation.findings}}
  end

  defp do_call("debugger.state", %{"slug" => slug} = args) do
    replay_metadata_only? = truthy?(Map.get(args, "replay_metadata_only"))
    include_replay_metadata? = include_replay_metadata?(Map.get(args, "include_replay_metadata"))

    with {:ok, compare_cursor_seq} <-
           parse_compare_cursor_seq(Map.get(args, "compare_cursor_seq")),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(slug,
             event_limit: parse_event_limit(args["event_limit"]),
             since_seq: parse_since_seq(args["since_seq"]),
             types: parse_event_types(args["types"])
           ) do
      events = Map.get(state, :events) || []
      snapshot_refs = Debugger.snapshot_reference_rows(events)
      runtime_fingerprints = DebuggerSupport.runtime_fingerprints_at_cursor(events, nil)
      runtime_fingerprint_digest = runtime_fingerprint_digest(runtime_fingerprints)

      runtime_fingerprint_compare =
        runtime_fingerprint_compare(
          events,
          runtime_fingerprints,
          resolve_cursor_seq(events, nil),
          compare_cursor_seq
        )

      replay_metadata =
        if include_replay_metadata? do
          DebuggerSupport.replay_metadata_at_cursor(events, nil)
        end

      if replay_metadata_only? do
        {:ok,
         %{
           slug: slug,
           event_window: length(events),
           runtime_fingerprint_digest: runtime_fingerprint_digest,
           snapshot_refs: snapshot_refs
         }
         |> maybe_put_runtime_fingerprint_compare(runtime_fingerprint_compare)
         |> maybe_put_replay_metadata(replay_metadata)}
      else
        {:ok,
         %{
           slug: slug,
           state: state,
           runtime_fingerprints: runtime_fingerprints,
           runtime_fingerprint_digest: runtime_fingerprint_digest,
           snapshot_refs: snapshot_refs
         }
         |> maybe_put_runtime_fingerprint_compare(runtime_fingerprint_compare)
         |> maybe_put_replay_metadata(replay_metadata)}
      end
    else
      {:error, "invalid compare_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger state failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.cursor_inspect", %{"slug" => slug} = args) do
    event_limit = parse_cursor_inspect_event_limit(args["event_limit"])
    include_replay_metadata? = include_replay_metadata?(Map.get(args, "include_replay_metadata"))
    replay_metadata_only? = truthy?(Map.get(args, "replay_metadata_only"))

    with {:ok, cursor_seq} <- parse_cursor_seq(args["cursor_seq"]),
         {:ok, compare_cursor_seq} <-
           parse_compare_cursor_seq(Map.get(args, "compare_cursor_seq")),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: event_limit) do
      events = Map.get(state, :events) || []
      snapshot_refs = Debugger.snapshot_reference_rows(events)

      update_limit = parse_inspect_table_limit(args["update_limit"], 40)
      protocol_limit = parse_inspect_table_limit(args["protocol_limit"], 40)
      render_limit = parse_inspect_table_limit(args["render_limit"], 24)
      lifecycle_limit = parse_inspect_table_limit(args["lifecycle_limit"], 12)

      resolved_cursor = resolve_cursor_seq(events, cursor_seq)
      diag = DebuggerSupport.diagnostics_preview_at_cursor(events, resolved_cursor)

      intro = DebuggerSupport.elm_introspect_at_cursor(events, resolved_cursor)

      runtime_fingerprints =
        DebuggerSupport.runtime_fingerprints_at_cursor(events, resolved_cursor)

      runtime_fingerprint_digest = runtime_fingerprint_digest(runtime_fingerprints)

      runtime_fingerprint_compare =
        runtime_fingerprint_compare(
          events,
          runtime_fingerprints,
          resolved_cursor,
          compare_cursor_seq
        )

      replay_metadata =
        if include_replay_metadata? do
          DebuggerSupport.replay_metadata_at_cursor(events, resolved_cursor)
        end

      payload =
        if replay_metadata_only? do
          %{
            slug: slug,
            cursor_seq: resolved_cursor,
            event_window: length(events),
            snapshot_refs: snapshot_refs
          }
        else
          %{
            slug: slug,
            cursor_seq: resolved_cursor,
            event_window: length(events),
            snapshot_refs: snapshot_refs,
            elmc_diagnostics: diag.rows,
            elmc_diagnostics_source: diag.source,
            elm_introspect: intro,
            runtime_fingerprints: runtime_fingerprints,
            runtime_fingerprint_digest: runtime_fingerprint_digest,
            update_messages:
              DebuggerSupport.update_messages_at_cursor(events, resolved_cursor, update_limit),
            protocol_exchange:
              DebuggerSupport.protocol_exchange_at_cursor(
                events,
                resolved_cursor,
                protocol_limit
              ),
            view_renders:
              DebuggerSupport.render_events_at_cursor(events, resolved_cursor, render_limit),
            lifecycle:
              DebuggerSupport.lifecycle_events_at_cursor(
                events,
                resolved_cursor,
                lifecycle_limit
              )
          }
        end

      {:ok,
       payload
       |> maybe_put_runtime_fingerprint_compare(runtime_fingerprint_compare)
       |> maybe_put_replay_metadata(replay_metadata)}
    else
      {:error, "invalid cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, "invalid compare_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger cursor_inspect failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.start", %{"slug" => slug}) do
    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.start_session(slug) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger start failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.reset", %{"slug" => slug}) do
    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.reset(slug) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger reset failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.reload", %{"slug" => slug, "rel_path" => rel_path} = args)
       when is_binary(rel_path) do
    source = Map.get(args, "source") || ""
    reason = Map.get(args, "reason") || "mcp_reload"
    source_root = Map.get(args, "source_root") || "watch"

    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <-
           Debugger.reload(slug, %{
             rel_path: rel_path,
             source: source,
             reason: reason,
             source_root: source_root
           }) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger reload failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.step", %{"slug" => slug} = args) do
    step_attrs = %{
      target: Map.get(args, "target"),
      message: Map.get(args, "message"),
      count: Map.get(args, "count")
    }

    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.step(slug, step_attrs) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger step failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.tick", %{"slug" => slug} = args) do
    tick_attrs = %{
      target: Map.get(args, "target"),
      count: Map.get(args, "count")
    }

    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.tick(slug, tick_attrs) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger tick failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.auto_tick_start", %{"slug" => slug} = args) do
    tick_attrs = %{
      target: Map.get(args, "target"),
      count: Map.get(args, "count"),
      interval_ms: Map.get(args, "interval_ms")
    }

    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.start_auto_tick(slug, tick_attrs) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger auto_tick_start failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.auto_tick_stop", %{"slug" => slug}) do
    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.stop_auto_tick(slug) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger auto_tick_stop failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.replay_recent", %{"slug" => slug} = args) do
    with {:ok, replay_mode} <- parse_replay_mode_arg(Map.get(args, "replay_mode")),
         {:ok, replay_drift_seq} <- parse_replay_drift_seq(Map.get(args, "replay_drift_seq")),
         {:ok, _cursor_seq} <- parse_cursor_seq(args["cursor_seq"]),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <-
           Debugger.replay_recent(slug, %{
             target: Map.get(args, "target"),
             count: Map.get(args, "count"),
             cursor_seq: Map.get(args, "cursor_seq"),
             replay_mode: replay_mode,
             replay_drift_seq: replay_drift_seq
           }) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, "invalid replay_mode (expected frozen|live)"} = err ->
        err

      {:error, "invalid replay_drift_seq (expected non-negative integer)"} = err ->
        err

      {:error, "invalid cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger replay_recent failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.continue_from_snapshot", %{"slug" => slug} = args) do
    with {:ok, _cursor_seq} <- parse_cursor_seq(args["cursor_seq"]),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <-
           Debugger.continue_from_snapshot(slug, %{
             cursor_seq: Map.get(args, "cursor_seq")
           }) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, "invalid cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger continue_from_snapshot failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.export_trace", %{"slug" => slug} = args) do
    with {:ok, compare_cursor_seq} <-
           parse_compare_cursor_seq(Map.get(args, "compare_cursor_seq")),
         {:ok, baseline_cursor_seq} <-
           parse_baseline_cursor_seq(Map.get(args, "baseline_cursor_seq")),
         {:ok, _project} <- fetch_project(slug),
         {:ok, export} <-
           Debugger.export_trace(slug,
             event_limit: parse_event_limit(args["event_limit"]),
             compare_cursor_seq: compare_cursor_seq,
             baseline_cursor_seq: baseline_cursor_seq
           ) do
      {:ok,
       %{
         slug: slug,
         export_json: export.json,
         sha256: export.sha256,
         byte_size: export.byte_size
       }}
    else
      {:error, "invalid compare_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, "invalid baseline_cursor_seq (expected non-negative integer)"} = err ->
        err

      {:error, reason} ->
        {:error, "debugger export_trace failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.import_trace", %{"slug" => slug, "export_json" => json} = args)
       when is_binary(json) do
    strict? = Map.get(args, "strict_slug", true)
    strict? = if strict? in [false, "false"], do: false, else: true

    opts = if strict?, do: [strict_slug: true], else: [strict_slug: false]
    expected_sha = Map.get(args, "expected_sha256")

    with {:ok, _project} <- fetch_project(slug),
         :ok <- verify_export_sha256(json, expected_sha),
         {:ok, state} <- Debugger.import_trace(slug, json, opts) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger import_trace failed: #{inspect(reason)}"}
    end
  end

  defp do_call("traces.export_write", args) do
    with {:ok, export} <- do_call("traces.export", args),
         :ok <- File.mkdir_p(trace_export_dir()),
         file_name <- trace_export_filename(export),
         absolute_path <- Path.join(trace_export_dir(), file_name),
         :ok <- File.write(absolute_path, export.export_json),
         {:ok, stat} <- File.stat(absolute_path) do
      {:ok,
       %{
         trace_id: export.trace_id,
         slug: export.slug,
         export_sha256: export.export_sha256,
         bytes: stat.size,
         path: absolute_path,
         file_name: file_name
       }}
    else
      {:error, reason} -> {:error, "trace export write failed: #{inspect(reason)}"}
    end
  end

  defp do_call("traces.exports_prune", args) do
    keep_latest =
      args
      |> Map.get("keep_latest", default_keep_latest())
      |> parse_prune_keep_latest()

    with {:ok, files} <- read_trace_export_files() do
      to_delete = Enum.drop(files, keep_latest)

      deleted =
        Enum.reduce(to_delete, [], fn file, acc ->
          case File.rm(file.path) do
            :ok -> [file.file_name | acc]
            {:error, _} -> acc
          end
        end)
        |> Enum.reverse()

      {:ok,
       %{
         keep_latest: keep_latest,
         deleted_count: length(deleted),
         deleted_files: deleted,
         remaining_count: max(length(files) - length(deleted), 0)
       }}
    else
      {:error, reason} -> {:error, "trace exports prune failed: #{inspect(reason)}"}
    end
  end

  defp do_call("traces.maintenance", args) do
    warn_count = parse_positive_integer(Map.get(args, "warn_count"), default_warn_count())
    warn_bytes = parse_positive_integer(Map.get(args, "warn_bytes"), default_warn_bytes())

    target_keep_latest =
      parse_prune_keep_latest(Map.get(args, "target_keep_latest", default_target_keep_latest()))

    apply? = Map.get(args, "apply") == true

    policy = %{
      warn_count: warn_count,
      warn_bytes: warn_bytes,
      keep_latest: default_keep_latest(),
      target_keep_latest: target_keep_latest
    }

    policy_validation = policy_validation_payload(policy)

    with {:ok, before} <- trace_health_payload(warn_count, warn_bytes) do
      should_prune? = before.status == "warn"
      pruned = apply? and should_prune?

      prune_result =
        if pruned do
          case do_call("traces.exports_prune", %{"keep_latest" => target_keep_latest}) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok,
           %{
             deleted_count: 0,
             deleted_files: [],
             remaining_count: before.trace_exports.total_count
           }}
        end

      with {:ok, prune_payload} <- prune_result,
           {:ok, health_after} <- trace_health_payload(warn_count, warn_bytes) do
        {:ok,
         %{
           mode: if(apply?, do: "apply", else: "dry_run"),
           status: if(pruned, do: "pruned", else: "no_change"),
           policy_validation: policy_validation,
           health_before: before,
           health_after: health_after,
           thresholds: %{warn_count: warn_count, warn_bytes: warn_bytes},
           target_keep_latest: target_keep_latest,
           prune: prune_payload
         }}
      else
        {:error, reason} -> {:error, "trace maintenance failed: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, "trace maintenance failed: #{inspect(reason)}"}
    end
  end

  defp do_call("sessions.recent_activity", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> parse_limit()

    with {:ok, since} <- parse_since(Map.get(args, "since")) do
      requested_slug = Map.get(args, "slug")

      projects =
        Projects.list_projects()
        |> maybe_filter_projects(requested_slug)
        |> Enum.map(fn project ->
          checks = CheckCache.recent(limit, project.slug) |> filter_since(since)

          latest_check =
            case CheckCache.latest(project.slug) do
              {:ok, entry} -> if keep_since?(entry, since), do: entry, else: nil
              {:error, :not_found} -> nil
            end

          latest_compile =
            case CompileCache.latest(project.slug) do
              {:ok, entry} -> if keep_since?(entry, since), do: entry, else: nil
              {:error, :not_found} -> nil
            end

          latest_manifest =
            case ManifestCache.latest(project.slug) do
              {:ok, entry} -> if keep_since?(entry, since), do: entry, else: nil
              {:error, :not_found} -> nil
            end

          latest_manifest_strict =
            case latest_manifest do
              %{result: result} when is_map(result) -> result[:strict?]
              _ -> nil
            end

          %{
            slug: project.slug,
            name: project.name,
            target_type: project.target_type,
            active: project.active,
            screenshot_count: screenshot_count(project.slug),
            latest_check: latest_check,
            latest_compile: latest_compile,
            latest_manifest: latest_manifest,
            latest_manifest_strict: latest_manifest_strict,
            recent_checks: checks,
            recent_compiles: CompileCache.recent(limit, project.slug) |> filter_since(since),
            recent_manifests: ManifestCache.recent(limit, project.slug) |> filter_since(since),
            recent_actions: recent_project_actions(project.slug, limit, since)
          }
        end)

      {:ok, %{projects: projects, limit: limit, slug: requested_slug, since: format_since(since)}}
    end
  end

  defp do_call("sessions.summary", args) do
    with {:ok, since} <- parse_since(Map.get(args, "since")) do
      requested_slug = Map.get(args, "slug")

      summaries =
        Projects.list_projects()
        |> maybe_filter_projects(requested_slug)
        |> Enum.map(fn project ->
          recent_checks =
            CheckCache.recent(50, project.slug)
            |> filter_since(since)

          recent_actions =
            recent_project_actions(project.slug, 100, since)

          latest_check_status =
            case CheckCache.latest(project.slug) do
              {:ok, entry} ->
                if keep_since?(entry, since), do: entry.result[:status], else: nil

              _ ->
                nil
            end

          latest_compile_status =
            case CompileCache.latest(project.slug) do
              {:ok, entry} ->
                if keep_since?(entry, since), do: entry.result[:status], else: nil

              _ ->
                nil
            end

          latest_manifest_status =
            case ManifestCache.latest(project.slug) do
              {:ok, entry} ->
                if keep_since?(entry, since), do: entry.result[:status], else: nil

              _ ->
                nil
            end

          latest_manifest_strict =
            case ManifestCache.latest(project.slug) do
              {:ok, entry} ->
                if keep_since?(entry, since), do: entry.result[:strict?], else: nil

              _ ->
                nil
            end

          %{
            slug: project.slug,
            active: project.active,
            target_type: project.target_type,
            latest_check_status: latest_check_status,
            latest_compile_status: latest_compile_status,
            latest_manifest_status: latest_manifest_status,
            latest_manifest_strict: latest_manifest_strict,
            checks_count: length(recent_checks),
            compiles_count: length(CompileCache.recent(50, project.slug) |> filter_since(since)),
            manifests_count:
              length(ManifestCache.recent(50, project.slug) |> filter_since(since)),
            actions_count: length(recent_actions),
            screenshots_count: screenshot_count(project.slug)
          }
        end)

      {:ok, %{projects: summaries, slug: requested_slug, since: format_since(since)}}
    end
  end

  defp do_call("sessions.trace_health", args) do
    warn_count = parse_positive_integer(Map.get(args, "warn_count"), default_warn_count())
    warn_bytes = parse_positive_integer(Map.get(args, "warn_bytes"), default_warn_bytes())

    policy = %{
      warn_count: warn_count,
      warn_bytes: warn_bytes,
      keep_latest: default_keep_latest(),
      target_keep_latest: default_target_keep_latest()
    }

    policy_validation = policy_validation_payload(policy)

    with {:ok, payload} <- trace_health_payload(warn_count, warn_bytes) do
      {:ok, Map.put(payload, :policy_validation, policy_validation)}
    else
      {:error, reason} -> {:error, "trace health failed: #{inspect(reason)}"}
    end
  end

  defp do_call(name, _args), do: {:error, "unknown tool: #{name}"}

  @spec build_trace_bundle(map()) :: tool_result()
  defp build_trace_bundle(args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> parse_limit()

    with {:ok, since} <- parse_since(Map.get(args, "since")),
         {:ok, trace_id} <- parse_trace_id(Map.get(args, "trace_id")),
         {:ok, requested_slug} <- parse_optional_slug(Map.get(args, "slug")) do
      audit_entries =
        Audit.recent(limit * 5)
        |> maybe_filter_trace_id(trace_id)
        |> maybe_filter_audit_slug(requested_slug)
        |> filter_since(since)
        |> Enum.take(limit)

      slug = requested_slug || infer_slug_from_audit_entries(audit_entries)

      check_entries = CheckCache.recent(limit, slug) |> filter_since(since)
      compile_entries = CompileCache.recent(limit, slug) |> filter_since(since)
      manifest_entries = ManifestCache.recent(limit, slug) |> filter_since(since)

      {:ok,
       %{
         trace_id: trace_id,
         slug: slug,
         limit: limit,
         since: format_since(since),
         audit_entries: audit_entries,
         compiler_context: %{
           latest: %{
             check: latest_entry(CheckCache, slug, since),
             compile: latest_entry(CompileCache, slug, since),
             manifest: latest_entry(ManifestCache, slug, since)
           },
           recent: %{
             checks: check_entries,
             compiles: compile_entries,
             manifests: manifest_entries
           }
         }
       }}
    end
  end

  @spec fetch_project(String.t()) :: {:ok, map()} | {:error, :project_not_found}
  defp fetch_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  @spec authorized?(String.t(), [capability()]) :: boolean()
  defp authorized?("projects.list", capabilities), do: :read in capabilities
  defp authorized?("projects.tree", capabilities), do: :read in capabilities
  defp authorized?("files.read", capabilities), do: :read in capabilities
  defp authorized?("packages.search", capabilities), do: :read in capabilities
  defp authorized?("packages.details", capabilities), do: :read in capabilities
  defp authorized?("packages.versions", capabilities), do: :read in capabilities
  defp authorized?("packages.readme", capabilities), do: :read in capabilities
  defp authorized?("projects.graph", capabilities), do: :read in capabilities
  defp authorized?("audit.recent", capabilities), do: :read in capabilities
  defp authorized?("compiler.check_cached", capabilities), do: :read in capabilities
  defp authorized?("compiler.check_recent", capabilities), do: :read in capabilities
  defp authorized?("compiler.compile_cached", capabilities), do: :read in capabilities
  defp authorized?("compiler.compile_recent", capabilities), do: :read in capabilities
  defp authorized?("compiler.manifest_cached", capabilities), do: :read in capabilities
  defp authorized?("compiler.manifest_recent", capabilities), do: :read in capabilities
  defp authorized?("sessions.recent_activity", capabilities), do: :read in capabilities
  defp authorized?("sessions.summary", capabilities), do: :read in capabilities
  defp authorized?("sessions.trace_health", capabilities), do: :read in capabilities
  defp authorized?("traces.bundle", capabilities), do: :read in capabilities
  defp authorized?("traces.summary", capabilities), do: :read in capabilities
  defp authorized?("traces.export", capabilities), do: :read in capabilities
  defp authorized?("traces.exports_list", capabilities), do: :read in capabilities
  defp authorized?("traces.policy", capabilities), do: :read in capabilities
  defp authorized?("traces.policy_validate", capabilities), do: :read in capabilities
  defp authorized?("debugger.state", capabilities), do: :read in capabilities
  defp authorized?("debugger.export_trace", capabilities), do: :read in capabilities
  defp authorized?("debugger.cursor_inspect", capabilities), do: :read in capabilities
  defp authorized?("projects.create", capabilities), do: :edit in capabilities
  defp authorized?("projects.delete", capabilities), do: :edit in capabilities
  defp authorized?("files.write", capabilities), do: :edit in capabilities
  defp authorized?("packages.add_to_elm_json", capabilities), do: :edit in capabilities
  defp authorized?("packages.remove_from_elm_json", capabilities), do: :edit in capabilities
  defp authorized?("traces.export_write", capabilities), do: :edit in capabilities
  defp authorized?("traces.exports_prune", capabilities), do: :edit in capabilities
  defp authorized?("traces.maintenance", capabilities), do: :edit in capabilities
  defp authorized?("debugger.start", capabilities), do: :edit in capabilities
  defp authorized?("debugger.reset", capabilities), do: :edit in capabilities
  defp authorized?("debugger.reload", capabilities), do: :edit in capabilities
  defp authorized?("debugger.step", capabilities), do: :edit in capabilities
  defp authorized?("debugger.tick", capabilities), do: :edit in capabilities
  defp authorized?("debugger.auto_tick_start", capabilities), do: :edit in capabilities
  defp authorized?("debugger.auto_tick_stop", capabilities), do: :edit in capabilities
  defp authorized?("debugger.replay_recent", capabilities), do: :edit in capabilities
  defp authorized?("debugger.continue_from_snapshot", capabilities), do: :edit in capabilities
  defp authorized?("debugger.import_trace", capabilities), do: :edit in capabilities
  defp authorized?("pebble.package", capabilities), do: :build in capabilities
  defp authorized?("pebble.install", capabilities), do: :build in capabilities
  defp authorized?("screenshots.capture", capabilities), do: :build in capabilities
  defp authorized?("compiler.check", capabilities), do: :build in capabilities
  defp authorized?("compiler.compile", capabilities), do: :build in capabilities
  defp authorized?("compiler.manifest", capabilities), do: :build in capabilities
  defp authorized?(_, _), do: false

  @spec add_if(list(), boolean(), list()) :: list()
  defp add_if(list, true, entries), do: list ++ entries
  defp add_if(list, false, _entries), do: list

  @spec count_files([map()]) :: non_neg_integer()
  defp count_files(nodes) when is_list(nodes) do
    Enum.reduce(nodes, 0, fn node, acc ->
      children = Map.get(node, :children, [])
      is_dir = Map.get(node, :type) == :dir

      if is_dir do
        acc + count_files(children)
      else
        acc + 1
      end
    end)
  end

  @spec parse_limit(term()) :: pos_integer()
  defp parse_limit(value) when is_integer(value), do: clamp_limit(value)

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> clamp_limit(parsed)
      _ -> 20
    end
  end

  defp parse_limit(_), do: 20

  @spec put_opt(keyword(), atom(), term()) :: keyword()
  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, _key, ""), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @spec put_opt_map(map(), String.t(), term()) :: map()
  defp put_opt_map(map, _key, nil), do: map
  defp put_opt_map(map, _key, ""), do: map
  defp put_opt_map(map, key, value), do: Map.put(map, key, value)

  @spec parse_platform_target(term()) :: term()
  defp parse_platform_target("watch"), do: :watch
  defp parse_platform_target("phone"), do: :phone
  defp parse_platform_target(_), do: nil

  @spec clamp_limit(integer()) :: pos_integer()
  defp clamp_limit(limit) when limit < 1, do: 1
  defp clamp_limit(limit) when limit > 200, do: 200
  defp clamp_limit(limit), do: limit

  @spec maybe_filter_projects([map()], maybe_slug()) :: [map()]
  defp maybe_filter_projects(projects, nil), do: projects
  defp maybe_filter_projects(projects, slug), do: Enum.filter(projects, &(&1.slug == slug))

  @spec recent_project_actions(String.t(), pos_integer(), maybe_since()) :: [map()]
  defp recent_project_actions(project_slug, limit, since) do
    Audit.recent(limit * 5)
    |> Enum.filter(fn entry ->
      args = Map.get(entry, "arguments", %{})
      Map.get(args, "slug") == project_slug
    end)
    |> filter_since(since)
    |> Enum.take(limit)
  end

  @spec screenshot_count(String.t()) :: non_neg_integer()
  defp screenshot_count(project_slug) do
    case Screenshots.list(project_slug, []) do
      {:ok, shots} -> length(shots)
      {:error, _reason} -> 0
    end
  end

  @spec parse_since(term()) :: {:ok, maybe_since()} | {:error, String.t()}
  defp parse_since(nil), do: {:ok, nil}
  defp parse_since(""), do: {:ok, nil}

  defp parse_since(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> {:error, "invalid since timestamp (expected ISO8601)"}
    end
  end

  defp parse_since(_), do: {:error, "invalid since timestamp (expected ISO8601)"}

  @spec parse_trace_id(term()) :: {:ok, maybe_trace_id()} | {:error, String.t()}
  defp parse_trace_id(nil), do: {:ok, nil}
  defp parse_trace_id(""), do: {:ok, nil}
  defp parse_trace_id(value) when is_binary(value), do: {:ok, value}
  defp parse_trace_id(_), do: {:error, "invalid trace_id (expected string)"}

  @spec parse_optional_slug(term()) :: {:ok, maybe_slug()} | {:error, String.t()}
  defp parse_optional_slug(nil), do: {:ok, nil}
  defp parse_optional_slug(""), do: {:ok, nil}
  defp parse_optional_slug(value) when is_binary(value), do: {:ok, value}
  defp parse_optional_slug(_), do: {:error, "invalid slug (expected string)"}

  @spec parse_prune_keep_latest(term()) :: non_neg_integer()
  defp parse_prune_keep_latest(value) when is_integer(value), do: max(value, 0)

  defp parse_prune_keep_latest(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> max(parsed, 0)
      _ -> default_keep_latest()
    end
  end

  defp parse_prune_keep_latest(_), do: default_keep_latest()

  @spec parse_positive_integer(term(), pos_integer()) :: pos_integer()
  defp parse_positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp parse_positive_integer(_value, fallback), do: fallback

  @spec parse_event_limit(term()) :: pos_integer()
  defp parse_event_limit(value) when is_integer(value) and value > 0, do: min(value, 500)

  defp parse_event_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed > 0 -> min(parsed, 500)
      _ -> 50
    end
  end

  defp parse_event_limit(_), do: 50

  @spec parse_since_seq(term()) :: non_neg_integer() | nil
  defp parse_since_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_since_seq(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_since_seq(_), do: nil

  @spec truthy?(term()) :: boolean()
  defp truthy?(value) when value in [true, 1, "1", "true", "TRUE", "True"], do: true
  defp truthy?(_), do: false

  @spec include_replay_metadata?(term()) :: boolean()
  defp include_replay_metadata?(nil), do: true

  defp include_replay_metadata?(value) when value in [false, 0, "0", "false", "FALSE", "False"],
    do: false

  defp include_replay_metadata?(_), do: true

  @spec parse_compare_cursor_seq(term()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_compare_cursor_seq(nil), do: {:ok, nil}

  defp parse_compare_cursor_seq(value) do
    case parse_cursor_seq(value) do
      {:ok, seq} -> {:ok, seq}
      {:error, _} -> {:error, "invalid compare_cursor_seq (expected non-negative integer)"}
    end
  end

  @spec parse_baseline_cursor_seq(term()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_baseline_cursor_seq(nil), do: {:ok, nil}

  defp parse_baseline_cursor_seq(value) do
    case parse_cursor_seq(value) do
      {:ok, seq} -> {:ok, seq}
      {:error, _} -> {:error, "invalid baseline_cursor_seq (expected non-negative integer)"}
    end
  end

  @spec runtime_fingerprint_digest(map()) :: map()
  defp runtime_fingerprint_digest(runtime_fingerprints) when is_map(runtime_fingerprints) do
    [:watch, :companion, :phone]
    |> Enum.reduce(%{}, fn surface, acc ->
      case Map.get(runtime_fingerprints, surface) do
        %{} = fp ->
          Map.put(acc, surface, %{
            runtime_mode: Map.get(fp, :runtime_mode),
            engine: Map.get(fp, :engine),
            execution_backend: Map.get(fp, :execution_backend),
            external_fallback_reason: Map.get(fp, :external_fallback_reason),
            runtime_model_source: Map.get(fp, :runtime_model_source),
            view_tree_source: Map.get(fp, :view_tree_source),
            target_numeric_key: Map.get(fp, :target_numeric_key),
            target_numeric_key_source: Map.get(fp, :target_numeric_key_source),
            target_boolean_key: Map.get(fp, :target_boolean_key),
            target_boolean_key_source: Map.get(fp, :target_boolean_key_source),
            active_target_key: Map.get(fp, :active_target_key),
            active_target_key_source: Map.get(fp, :active_target_key_source),
            protocol_inbound_count: Map.get(fp, :protocol_inbound_count),
            protocol_message_count: Map.get(fp, :protocol_message_count),
            protocol_last_inbound_message: Map.get(fp, :protocol_last_inbound_message),
            runtime_model_sha256: Map.get(fp, :runtime_model_sha256),
            view_tree_sha256: Map.get(fp, :view_tree_sha256)
          })

        _ ->
          acc
      end
    end)
  end

  @spec runtime_fingerprint_compare([map()], map(), integer() | nil, integer() | nil) ::
          map() | nil
  defp runtime_fingerprint_compare(_events, _current, _current_seq, nil), do: nil

  defp runtime_fingerprint_compare(_events, _current, current_seq, _compare_cursor_seq)
       when not is_integer(current_seq),
       do: nil

  defp runtime_fingerprint_compare(events, current, current_seq, compare_cursor_seq)
       when is_list(events) and is_map(current) and is_integer(compare_cursor_seq) do
    resolved_compare_cursor = resolve_cursor_seq(events, compare_cursor_seq)
    compare = DebuggerSupport.runtime_fingerprints_at_cursor(events, resolved_compare_cursor)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current_fp = Map.get(current, surface)
        compare_fp = Map.get(compare, surface)
        current_digest = runtime_fingerprint_digest(%{surface => current_fp})[surface]
        compare_digest = runtime_fingerprint_digest(%{surface => compare_fp})[surface]

        if is_map(current_digest) or is_map(compare_digest) do
          backend_changed =
            Map.get(current_digest || %{}, :execution_backend) !=
              Map.get(compare_digest || %{}, :execution_backend) or
              Map.get(current_digest || %{}, :external_fallback_reason) !=
                Map.get(compare_digest || %{}, :external_fallback_reason)

          key_target_changed =
            Map.get(current_digest || %{}, :target_numeric_key) !=
              Map.get(compare_digest || %{}, :target_numeric_key) or
              Map.get(current_digest || %{}, :target_numeric_key_source) !=
                Map.get(compare_digest || %{}, :target_numeric_key_source) or
              Map.get(current_digest || %{}, :target_boolean_key) !=
                Map.get(compare_digest || %{}, :target_boolean_key) or
              Map.get(current_digest || %{}, :target_boolean_key_source) !=
                Map.get(compare_digest || %{}, :target_boolean_key_source) or
              Map.get(current_digest || %{}, :active_target_key) !=
                Map.get(compare_digest || %{}, :active_target_key) or
              Map.get(current_digest || %{}, :active_target_key_source) !=
                Map.get(compare_digest || %{}, :active_target_key_source)

          Map.put(acc, surface, %{
            changed: current_digest != compare_digest or key_target_changed,
            backend_changed: backend_changed,
            key_target_changed: key_target_changed,
            current: current_digest,
            compare: compare_digest
          })
        else
          acc
        end
      end)

    backend_drift_detail = RuntimeFingerprintDrift.backend_drift_detail(%{surfaces: surfaces})

    key_target_drift_detail =
      RuntimeFingerprintDrift.key_target_drift_detail(%{surfaces: surfaces})

    drift_detail =
      RuntimeFingerprintDrift.merge_drift_detail(backend_drift_detail, key_target_drift_detail)

    %{
      cursor_seq: current_seq,
      compare_cursor_seq: resolved_compare_cursor,
      backend_changed_surface_count:
        surfaces
        |> Map.values()
        |> Enum.count(fn row -> Map.get(row, :backend_changed) end),
      key_target_changed_surface_count:
        surfaces
        |> Map.values()
        |> Enum.count(fn row -> Map.get(row, :key_target_changed) end),
      backend_drift_detail: backend_drift_detail,
      key_target_drift_detail: key_target_drift_detail,
      drift_detail: drift_detail,
      surfaces: surfaces
    }
  end

  defp runtime_fingerprint_compare(_events, _current, _current_seq, _compare_cursor_seq), do: nil

  @spec maybe_put_runtime_fingerprint_compare(map(), map() | nil) :: map()
  defp maybe_put_runtime_fingerprint_compare(payload, nil), do: payload

  defp maybe_put_runtime_fingerprint_compare(payload, compare) when is_map(compare) do
    Map.put(payload, :runtime_fingerprint_compare, compare)
  end

  @spec parse_replay_mode_arg(term()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_replay_mode_arg(nil), do: {:ok, nil}
  defp parse_replay_mode_arg("frozen"), do: {:ok, "frozen"}
  defp parse_replay_mode_arg("live"), do: {:ok, "live"}
  defp parse_replay_mode_arg(_), do: {:error, "invalid replay_mode (expected frozen|live)"}

  @spec parse_replay_drift_seq(term()) :: {:ok, non_neg_integer() | nil} | {:error, String.t()}
  defp parse_replay_drift_seq(nil), do: {:ok, nil}

  defp parse_replay_drift_seq(n) when is_integer(n) and n >= 0, do: {:ok, n}

  defp parse_replay_drift_seq(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i >= 0 -> {:ok, i}
      _ -> {:error, "invalid replay_drift_seq (expected non-negative integer)"}
    end
  end

  defp parse_replay_drift_seq(_),
    do: {:error, "invalid replay_drift_seq (expected non-negative integer)"}

  @spec maybe_put_replay_metadata(map(), map() | nil) :: map()
  defp maybe_put_replay_metadata(payload, replay_metadata) when is_map(payload) do
    if is_nil(replay_metadata) and Map.has_key?(payload, :replay_metadata) do
      Map.delete(payload, :replay_metadata)
    else
      case replay_metadata do
        nil -> payload
        metadata -> Map.put(payload, :replay_metadata, metadata)
      end
    end
  end

  @spec parse_cursor_inspect_event_limit(term()) :: term()
  defp parse_cursor_inspect_event_limit(value) when is_integer(value) and value > 0,
    do: min(value, 500)

  defp parse_cursor_inspect_event_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> min(n, 500)
      _ -> 500
    end
  end

  defp parse_cursor_inspect_event_limit(_), do: 500

  @spec parse_cursor_seq(term()) :: term()
  defp parse_cursor_seq(nil), do: {:ok, nil}

  defp parse_cursor_seq(n) when is_integer(n) and n >= 0, do: {:ok, n}

  defp parse_cursor_seq(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i >= 0 -> {:ok, i}
      _ -> {:error, "invalid cursor_seq (expected non-negative integer)"}
    end
  end

  defp parse_cursor_seq(_), do: {:error, "invalid cursor_seq (expected non-negative integer)"}

  @spec parse_inspect_table_limit(term(), term()) :: term()
  defp parse_inspect_table_limit(nil, default), do: default

  defp parse_inspect_table_limit(n, _default) when is_integer(n) and n > 0, do: min(n, 100)

  defp parse_inspect_table_limit(n, default) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i > 0 -> min(i, 100)
      _ -> default
    end
  end

  defp parse_inspect_table_limit(_, default), do: default

  @spec resolve_cursor_seq([map()], integer() | nil) :: integer() | nil
  defp resolve_cursor_seq(events, requested_seq) when is_list(events) do
    CursorSeq.resolve_at_or_before(events, requested_seq)
  end

  @spec parse_event_types(term()) :: [String.t()] | nil
  defp parse_event_types(nil), do: nil

  defp parse_event_types(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      items -> items
    end
  end

  defp parse_event_types(_), do: nil

  @spec format_since(maybe_since()) :: String.t() | nil
  defp format_since(nil), do: nil
  defp format_since(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @spec filter_since([map()], maybe_since()) :: [map()]
  defp filter_since(entries, nil), do: entries

  defp filter_since(entries, %DateTime{} = since),
    do: Enum.filter(entries, &keep_since?(&1, since))

  @spec keep_since?(map(), maybe_since()) :: boolean()
  defp keep_since?(_entry, nil), do: true

  defp keep_since?(entry, %DateTime{} = since) do
    case entry_datetime(entry) do
      {:ok, dt} -> DateTime.compare(dt, since) in [:eq, :gt]
      :error -> false
    end
  end

  @spec entry_datetime(map()) :: {:ok, DateTime.t()} | :error
  defp entry_datetime(entry) when is_map(entry) do
    at = Map.get(entry, :at) || Map.get(entry, "at")

    if is_binary(at) do
      case DateTime.from_iso8601(at) do
        {:ok, dt, _offset} -> {:ok, dt}
        _ -> :error
      end
    else
      :error
    end
  end

  @spec maybe_filter_trace_id([map()], maybe_trace_id()) :: [map()]
  defp maybe_filter_trace_id(entries, nil), do: entries

  defp maybe_filter_trace_id(entries, trace_id),
    do: Enum.filter(entries, &(&1["trace_id"] == trace_id))

  @spec maybe_filter_audit_slug([map()], maybe_slug()) :: [map()]
  defp maybe_filter_audit_slug(entries, nil), do: entries

  defp maybe_filter_audit_slug(entries, slug) do
    Enum.filter(entries, fn entry ->
      entry
      |> Map.get("arguments", %{})
      |> Map.get("slug") == slug
    end)
  end

  @spec infer_slug_from_audit_entries([map()]) :: maybe_slug()
  defp infer_slug_from_audit_entries(entries) do
    entries
    |> Enum.find_value(fn entry ->
      entry
      |> Map.get("arguments", %{})
      |> Map.get("slug")
    end)
  end

  @spec latest_entry(module(), maybe_slug(), maybe_since()) :: map() | nil
  defp latest_entry(_cache_module, nil, _since), do: nil

  defp latest_entry(cache_module, slug, since) do
    case cache_module.latest(slug) do
      {:ok, entry} -> if keep_since?(entry, since), do: entry, else: nil
      {:error, :not_found} -> nil
    end
  end

  @spec status_of_entry(map() | nil) :: term() | nil
  defp status_of_entry(nil), do: nil

  defp status_of_entry(entry) when is_map(entry) do
    entry
    |> Map.get(:result, %{})
    |> Map.get(:status)
  end

  @spec strict_of_entry(map() | nil) :: boolean() | nil
  defp strict_of_entry(nil), do: nil

  defp strict_of_entry(entry) when is_map(entry) do
    entry
    |> Map.get(:result, %{})
    |> Map.get(:strict?)
  end

  @spec action_counts([map()]) :: [map()]
  defp action_counts(entries) when is_list(entries) do
    entries
    |> Enum.group_by(&Map.get(&1, "action", "unknown"))
    |> Enum.map(fn {action, grouped} ->
      %{
        action: action,
        total: length(grouped),
        ok: Enum.count(grouped, &(Map.get(&1, "status") == "ok")),
        error: Enum.count(grouped, &(Map.get(&1, "status") == "error"))
      }
    end)
    |> Enum.sort_by(& &1.action)
  end

  @spec encode_canonical_json(term()) :: String.t()
  defp encode_canonical_json(value) when is_map(value) do
    members =
      value
      |> Enum.map(fn {key, member} -> {to_string(key), member} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, member} ->
        Jason.encode!(key) <> ":" <> encode_canonical_json(member)
      end)

    "{" <> members <> "}"
  end

  defp encode_canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode_canonical_json/1) <> "]"
  end

  defp encode_canonical_json(value), do: Jason.encode!(value)

  @spec trace_export_filename(map()) :: String.t()
  defp trace_export_filename(export) do
    slug = sanitize_segment(export.slug || "all")
    trace = sanitize_segment(export.trace_id || "all")
    "trace-export-#{slug}-#{trace}-#{export.export_sha256}.json"
  end

  @spec sanitize_segment(String.t()) :: String.t()
  defp sanitize_segment(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "all"
      cleaned -> cleaned
    end
  end

  @spec trace_export_dir() :: String.t()
  defp trace_export_dir do
    Path.join(:code.priv_dir(:ide), "mcp/trace_exports")
  end

  @spec read_trace_export_files() :: {:ok, [map()]} | {:error, term()}
  defp read_trace_export_files do
    case File.ls(trace_export_dir()) do
      {:ok, names} ->
        entries =
          names
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(fn file_name ->
            path = Path.join(trace_export_dir(), file_name)

            with {:ok, stat} <- File.stat(path),
                 {:ok, modified_at} <- NaiveDateTime.from_erl(stat.mtime) do
              %{
                file_name: file_name,
                path: path,
                bytes: stat.size,
                modified_at:
                  DateTime.from_naive!(modified_at, "Etc/UTC") |> DateTime.to_iso8601(),
                sort_key: stat.mtime
              }
            else
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.sort_key, :desc)

        {:ok, entries}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec trace_health_payload(pos_integer(), pos_integer()) :: {:ok, map()} | {:error, term()}
  defp trace_health_payload(warn_count, warn_bytes) do
    with {:ok, files} <- read_trace_export_files() do
      total_count = length(files)
      total_bytes = Enum.reduce(files, 0, fn file, acc -> file.bytes + acc end)
      newest = files |> List.first() |> then(&(&1 && &1.modified_at))
      oldest = files |> List.last() |> then(&(&1 && &1.modified_at))

      over_count = total_count > warn_count
      over_bytes = total_bytes > warn_bytes

      status =
        if over_count or over_bytes do
          "warn"
        else
          "ok"
        end

      recommendation =
        cond do
          over_count and over_bytes ->
            "Prune exports by count and size pressure."

          over_count ->
            "Prune exports to reduce file count."

          over_bytes ->
            "Prune exports to reduce disk usage."

          true ->
            "No cleanup needed."
        end

      suggested_keep_latest =
        cond do
          total_count <= warn_count -> total_count
          true -> warn_count
        end

      {:ok,
       %{
         status: status,
         recommendation: recommendation,
         trace_exports: %{
           total_count: total_count,
           total_bytes: total_bytes,
           newest_modified_at: newest,
           oldest_modified_at: oldest
         },
         thresholds: %{
           warn_count: warn_count,
           warn_bytes: warn_bytes
         },
         suggested_keep_latest: suggested_keep_latest
       }}
    end
  end

  @spec validate_trace_policy(map()) :: [map()]
  defp validate_trace_policy(policy) when is_map(policy) do
    []
    |> maybe_add_finding(
      policy.warn_count <= 0,
      "error",
      "warn_count_non_positive",
      "warn_count should be greater than zero."
    )
    |> maybe_add_finding(
      policy.warn_bytes <= 0,
      "error",
      "warn_bytes_non_positive",
      "warn_bytes should be greater than zero."
    )
    |> maybe_add_finding(
      policy.target_keep_latest > policy.keep_latest,
      "warning",
      "target_keep_exceeds_keep",
      "target_keep_latest is higher than keep_latest; prune target may be ineffective."
    )
    |> maybe_add_finding(
      policy.keep_latest > policy.warn_count,
      "warning",
      "keep_exceeds_warn_count",
      "keep_latest is higher than warn_count; maintenance may remain in warning state after prune."
    )
    |> maybe_add_finding(
      policy.warn_bytes < 1_048_576,
      "warning",
      "warn_bytes_low",
      "warn_bytes is below 1 MiB; this may cause noisy maintenance warnings."
    )
  end

  @spec findings_status([map()]) :: String.t()
  defp findings_status(findings) when is_list(findings) do
    cond do
      Enum.any?(findings, &(&1.severity == "error")) -> "error"
      findings != [] -> "warn"
      true -> "ok"
    end
  end

  @spec policy_validation_payload(map()) :: map()
  defp policy_validation_payload(policy) when is_map(policy) do
    findings = validate_trace_policy(policy)
    %{status: findings_status(findings), findings: findings}
  end

  @spec maybe_add_finding([map()], boolean(), String.t(), String.t(), String.t()) :: [map()]
  defp maybe_add_finding(findings, false, _severity, _code, _message), do: findings

  defp maybe_add_finding(findings, true, severity, code, message) do
    findings ++ [%{severity: severity, code: code, message: message}]
  end

  @spec default_warn_count() :: pos_integer()
  defp default_warn_count do
    trace_policy()
    |> Keyword.get(:warn_count, 200)
  end

  @spec default_warn_bytes() :: pos_integer()
  defp default_warn_bytes do
    trace_policy()
    |> Keyword.get(:warn_bytes, 50 * 1024 * 1024)
  end

  @spec default_keep_latest() :: non_neg_integer()
  defp default_keep_latest do
    trace_policy()
    |> Keyword.get(:keep_latest, 50)
  end

  @spec default_target_keep_latest() :: non_neg_integer()
  defp default_target_keep_latest do
    trace_policy()
    |> Keyword.get(:target_keep_latest, default_keep_latest())
  end

  @spec trace_policy() :: keyword()
  defp trace_policy do
    mcp_tools_config()
    |> Keyword.get(:trace_policy, [])
  end

  @spec mcp_tools_config() :: keyword()
  defp mcp_tools_config do
    Application.get_env(:ide, __MODULE__, [])
  end

  @spec compiler_module() :: module()
  defp compiler_module do
    mcp_tools_config()
    |> Keyword.get(:compiler_module, Compiler)
  end

  @spec pebble_toolchain_module() :: module()
  defp pebble_toolchain_module do
    mcp_tools_config()
    |> Keyword.get(:pebble_toolchain_module, PebbleToolchain)
  end

  @spec screenshots_module() :: module()
  defp screenshots_module do
    mcp_tools_config()
    |> Keyword.get(:screenshots_module, Screenshots)
  end

  @spec resolve_install_package_path(map(), map(), module()) ::
          {:ok, String.t()} | {:error, term()}
  defp resolve_install_package_path(project, args, toolchain) do
    case Map.get(args, "package_path") do
      path when is_binary(path) and path != "" ->
        resolved = Path.expand(path)

        if File.exists?(resolved) do
          {:ok, resolved}
        else
          {:error, {:package_path_not_found, resolved}}
        end

      _ ->
        toolchain.package(project.slug,
          workspace_root: Projects.project_workspace_path(project),
          target_type: project.target_type,
          project_name: project.name
        )
        |> case do
          {:ok, %{artifact_path: artifact_path}} -> {:ok, artifact_path}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec parse_logs_snapshot_seconds(term()) :: pos_integer()
  defp parse_logs_snapshot_seconds(value) when is_integer(value) and value >= 1 do
    min(value, 30)
  end

  defp parse_logs_snapshot_seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 1 -> min(parsed, 30)
      _ -> 4
    end
  end

  defp parse_logs_snapshot_seconds(_), do: 4

  @spec verify_export_sha256(String.t(), term()) :: :ok | {:error, term()}
  defp verify_export_sha256(_json, nil), do: :ok
  defp verify_export_sha256(_json, ""), do: :ok

  defp verify_export_sha256(json, expected) when is_binary(json) do
    expected_normalized = expected |> to_string() |> String.trim() |> String.downcase()

    actual =
      :crypto.hash(:sha256, json)
      |> Base.encode16(case: :lower)

    if expected_normalized == actual do
      :ok
    else
      {:error, {:sha256_mismatch, %{expected: expected_normalized, actual: actual}}}
    end
  end
end
