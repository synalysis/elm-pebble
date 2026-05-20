defmodule Ide.Mcp.Tools do
  @moduledoc """
  Capability-scoped MCP tool registry and dispatcher for IDE operations.
  """

  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Compiler.Cache, as: CompileCache
  alias Ide.AppStore.Publisher, as: AppStorePublisher
  alias Ide.Compiler.ManifestCache
  alias Ide.Mcp.Audit
  alias Ide.Mcp.CheckCache
  alias Ide.Packages
  alias Ide.EmulatorSupport
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.Debugger
  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.PublishFlow

  @type capability :: :read | :edit | :build | :publish
  @type tool_result :: {:ok, map()} | {:error, String.t()}
  @type maybe_since :: DateTime.t() | nil
  @type maybe_slug :: String.t() | nil
  @type maybe_trace_id :: String.t() | nil
  @tool_version "1.0.0"
  @catalog_version "2026-05-28"

  @simulator_settings_schema %{
    type: "object",
    additionalProperties: false,
    properties: %{
      battery_percent: %{type: "integer", minimum: 0, maximum: 100},
      charging: %{type: "boolean"},
      connected: %{type: "boolean"},
      clock_24h: %{type: "boolean"},
      use_simulated_time: %{
        type: "boolean",
        description:
          "When true, current-time device APIs and time-change subscriptions use simulated_date/simulated_time instead of the host clock."
      },
      simulated_time: %{
        type: "string",
        description:
          "Optional debugger clock time in HH:MM or HH:MM:SS. Used when use_simulated_time is true."
      },
      simulated_date: %{
        type: "string",
        description:
          "Optional debugger clock date in YYYY-MM-DD. Used with simulated_time for current-date/time device APIs."
      },
      latitude: %{type: "number", minimum: -90, maximum: 90},
      longitude: %{type: "number", minimum: -180, maximum: 180},
      accuracy: %{type: "number", minimum: 0, maximum: 100_000}
    }
  }

  @github_settings_schema %{
    type: "object",
    additionalProperties: false,
    properties: %{
      owner: %{type: "string"},
      repo: %{type: "string"},
      branch: %{type: "string"},
      visibility: %{type: "string", enum: ["private", "public"]}
    }
  }

  @release_defaults_schema %{
    type: "object",
    additionalProperties: false,
    properties: %{
      version_label: %{type: "string"},
      tags: %{type: "string"},
      target_platforms: %{type: "array", items: %{type: "string"}},
      capabilities: %{type: "array", items: %{type: "string"}}
    }
  }

  @read_tools [
    %{
      name: "projects.list",
      description: "List known IDE projects.",
      inputSchema: %{type: "object", additionalProperties: false, properties: %{}}
    },
    %{
      name: "projects.settings",
      description:
        "Read persisted project settings used by IDE automation, including release defaults, GitHub config, and debugger settings.",
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
      name: "files.stat",
      description:
        "Return metadata for a source file, including byte size, mtime, and SHA-256 revision hash.",
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
      name: "files.read_range",
      description: "Read a line range from a source file in a project root.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "source_root", "rel_path", "offset", "limit"],
        properties: %{
          slug: %{type: "string"},
          source_root: %{type: "string"},
          rel_path: %{type: "string"},
          offset: %{type: "integer", minimum: 1, description: "1-based first line to read."},
          limit: %{type: "integer", minimum: 1, maximum: 1000}
        }
      }
    },
    %{
      name: "files.search",
      description: "Search project source files with a literal text query.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "query"],
        properties: %{
          slug: %{type: "string"},
          query: %{type: "string"},
          source_root: %{type: "string"},
          limit: %{type: "integer", minimum: 1, maximum: 200}
        }
      }
    },
    %{
      name: "projects.diff",
      description: "Return git diff output for one project workspace, when available.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          limit_bytes: %{type: "integer", minimum: 1, maximum: 200_000}
        }
      }
    },
    %{
      name: "screenshots.list",
      description:
        "List saved screenshots for a project, including target device, timestamp, URL, and stored path.",
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
      name: "screenshots.read",
      description:
        "Read one saved project screenshot as base64-encoded binary data with MIME type and metadata.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "emulator_target", "filename"],
        properties: %{
          slug: %{type: "string", description: "Project slug."},
          emulator_target: %{type: "string", description: "Target device/emulator folder."},
          filename: %{
            type: "string",
            description: "Screenshot filename returned by screenshots.list."
          }
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
      name: "packages.module_docs",
      description:
        "Read Markdown API documentation for one exposed Elm package module, including internal Pebble packages.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["package", "module"],
        properties: %{
          package: %{type: "string"},
          module: %{type: "string"},
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
    },
    %{
      name: "debugger.render_tree",
      description:
        "Read the current debugger-rendered tree and flattened node bounds for a runtime surface.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{
            type: "string",
            enum: ["watch", "companion", "phone"],
            description: "Runtime surface to inspect (default: watch)."
          },
          include_tree: %{
            type: "boolean",
            description: "If true, include the full normalized rendered tree."
          }
        }
      }
    },
    %{
      name: "debugger.preview_diagnostics",
      description:
        "Explain how the debugger preview tree was selected for a runtime surface, including runtime output counts, fallback source, latest render events, and compact fingerprints.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{
            type: "string",
            enum: ["watch", "companion", "phone"],
            description: "Runtime surface to diagnose (default: watch)."
          },
          event_limit: %{
            type: "integer",
            minimum: 1,
            maximum: 500,
            description: "Debugger event window used for render/lifecycle context (default: 100)."
          }
        }
      }
    },
    %{
      name: "debugger.models",
      description:
        "Read compact watch, companion, and phone debugger models without full event snapshots.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{
            type: "string",
            enum: ["watch", "companion", "phone"],
            description: "Optional single runtime surface."
          },
          include_view_output: %{
            type: "boolean",
            description: "If true, include runtime_view_output rows in returned models."
          }
        }
      }
    },
    %{
      name: "debugger.timeline",
      description: "Read compact debugger timeline rows without full runtime snapshots.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          event_limit: %{type: "integer", minimum: 1, maximum: 500},
          since_seq: %{type: "integer", minimum: 0},
          types: %{
            type: "array",
            items: %{type: "string"},
            description: "Optional event type filter list."
          }
        }
      }
    },
    %{
      name: "debugger.surface_state",
      description:
        "Read one debugger surface model, runtime fingerprint, protocol messages, and optional render bounds.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          target: %{
            type: "string",
            enum: ["watch", "companion", "phone"],
            description: "Runtime surface to inspect (default: watch)."
          },
          include_view_output: %{
            type: "boolean",
            description: "If true, include runtime_view_output rows in the returned model."
          },
          include_render_tree: %{
            type: "boolean",
            description: "If true, include flattened rendered node bounds for the surface."
          }
        }
      }
    },
    %{
      name: "debugger.simulator_settings",
      description:
        "Read persisted and active debugger simulator inputs for watch device data and companion APIs.",
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
      name: "debugger.configuration",
      description:
        "Read persisted companion configuration values and the current debugger configuration model.",
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
      name: "debugger.auto_fire",
      description:
        "Read debugger auto-fire settings persisted for a project and active runtime state.",
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
      name: "debugger.disabled_subscriptions",
      description: "Read debugger subscription enable/disable settings for a project.",
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
      name: "debugger.watch_profiles",
      description: "List watch profiles available to debugger launch contexts.",
      inputSchema: %{type: "object", additionalProperties: false, properties: %{}}
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
              "watchface-yes",
              "watchface-tangram-time",
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
      name: "projects.update_settings",
      description:
        "Update safe persisted project settings such as name, target type, release defaults, GitHub config, and selected debugger/emulator preferences.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          name: %{type: "string"},
          target_type: %{type: "string", enum: ["app", "watchface", "companion"]},
          active: %{type: "boolean"},
          release_defaults: @release_defaults_schema,
          github: @github_settings_schema,
          debugger: %{
            type: "object",
            additionalProperties: false,
            properties: %{
              timeline_mode: %{type: "string", enum: ["watch", "companion", "mixed", "separate"]},
              watch_profile_id: %{type: "string"},
              emulator_target: %{type: "string"},
              emulator_mode: %{type: "string", enum: ["embedded", "external", "wasm"]}
            }
          }
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
      name: "files.patch",
      description:
        "Replace one expected string in a source file, guarded by optional SHA-256 revision.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "source_root", "rel_path", "old_string", "new_string"],
        properties: %{
          slug: %{type: "string"},
          source_root: %{type: "string"},
          rel_path: %{type: "string"},
          old_string: %{type: "string"},
          new_string: %{type: "string"},
          expected_sha256: %{
            type: "string",
            description: "Optional SHA-256 of current file content from files.stat."
          }
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
      name: "debugger.set_watch_profile",
      description: "Set the debugger watch profile and relaunch context for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "watch_profile_id"],
        properties: %{
          slug: %{type: "string"},
          watch_profile_id: %{type: "string"},
          launch_reason: %{
            type: "string",
            description: "Optional launch reason constructor name, defaulting to LaunchUser."
          }
        }
      }
    },
    %{
      name: "debugger.set_simulator_settings",
      description:
        "Persist and apply debugger simulator inputs for watch device data and companion geolocation.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "settings"],
        properties: %{
          slug: %{type: "string"},
          settings: @simulator_settings_schema
        }
      }
    },
    %{
      name: "debugger.save_configuration",
      description: "Persist and apply companion configuration values in the debugger.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "values"],
        properties: %{
          slug: %{type: "string"},
          values: %{type: "object", additionalProperties: true}
        }
      }
    },
    %{
      name: "debugger.set_auto_fire",
      description: "Persist and apply debugger natural subscription auto-fire settings.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "target", "enabled"],
        properties: %{
          slug: %{type: "string"},
          target: %{type: "string", enum: ["watch", "companion", "protocol", "phone"]},
          trigger: %{type: "string"},
          enabled: %{type: "boolean"}
        }
      }
    },
    %{
      name: "debugger.set_subscription_enabled",
      description: "Persist and apply debugger subscription enable/disable settings.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "target", "trigger", "enabled"],
        properties: %{
          slug: %{type: "string"},
          target: %{type: "string", enum: ["watch", "companion", "protocol", "phone"]},
          trigger: %{type: "string"},
          enabled: %{type: "boolean"}
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
              "watch | protocol | phone - drives which surface leads the hot-reload simulation.",
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
      name: "publish.prepare",
      description:
        "Build the PBW, validate publish readiness, and export publish manifest plus release notes.",
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
      name: "publish.validate",
      description:
        "Validate publish readiness for a project. By default this packages the project first so appinfo and PBW checks use current artifacts.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          package: %{
            type: "boolean",
            description:
              "If false, validate the provided artifact_path/app_root without building."
          },
          artifact_path: %{type: "string"},
          app_root: %{type: "string"}
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
      name: "compiler.check_source_root",
      description: "Run the editor-style compiler check for one source root.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug", "source_root"],
        properties: %{
          slug: %{type: "string"},
          source_root: %{
            type: "string",
            description: "Source root to check, such as watch, protocol, or phone."
          }
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

  @publish_tools [
    %{
      name: "publish.submit",
      description:
        "Submit a prepared release through the App Store API. Requires publish capability and can package first when app_root is omitted.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        required: ["slug"],
        properties: %{
          slug: %{type: "string"},
          app_root: %{type: "string"},
          release_notes: %{
            type: "string",
            description:
              "User-facing release notes sent to the App Store. Omit to submit an empty changelog."
          },
          is_published: %{type: "boolean"},
          all_platforms: %{type: "boolean"},
          gif_all_platforms: %{type: "boolean"},
          firebase_id_token: %{type: "string"}
        }
      }
    }
  ]
  @all_tools @read_tools ++ @edit_tools ++ @build_tools ++ @publish_tools
  @public_tool_names_by_internal Map.new(@all_tools, fn %{name: name} ->
                                   {name, String.replace(name, ".", "_")}
                                 end)
  @internal_tool_names_by_public Map.new(@public_tool_names_by_internal, fn {internal, public} ->
                                   {public, internal}
                                 end)
  @internal_tool_names MapSet.new(Map.keys(@public_tool_names_by_internal))

  @spec tool_definitions([capability()]) :: [map()]
  def tool_definitions(capabilities) do
    []
    |> add_if(:read in capabilities, @read_tools)
    |> add_if(:edit in capabilities, @edit_tools)
    |> add_if(:build in capabilities, @build_tools)
    |> add_if(:publish in capabilities, @publish_tools)
    |> Enum.map(&Map.put_new(&1, :version, @tool_version))
    |> Enum.map(&publish_tool_name/1)
    |> patch_emulator_mode_tool_schemas()
  end

  @spec catalog_version() :: String.t()
  def catalog_version, do: @catalog_version

  @spec call(String.t(), map(), [capability()]) :: {:ok, map()} | {:error, String.t()}
  def call(name, args, capabilities) when is_binary(name) and is_map(args) do
    internal_name = internal_tool_name(name)

    if authorized?(internal_name, capabilities) do
      do_call(internal_name, args)
    else
      {:error, "tool not permitted by current capability scope"}
    end
  end

  @spec audit_arguments(String.t(), map()) :: map()
  def audit_arguments(name, args) when is_binary(name) and is_map(args) do
    name
    |> internal_tool_name()
    |> do_audit_arguments(args)
  end

  @spec do_audit_arguments(String.t(), map()) :: map()
  defp do_audit_arguments("files.write", %{"content" => content} = args)
       when is_binary(content) do
    args
    |> Map.drop(["content"])
    |> Map.put("content_redacted", true)
    |> Map.put("content_bytes", byte_size(content))
  end

  defp do_audit_arguments("files.patch", args) do
    args
    |> redact_patch_argument("old_string")
    |> redact_patch_argument("new_string")
  end

  defp do_audit_arguments("debugger.import_trace", %{"export_json" => json} = args)
       when is_binary(json) do
    args
    |> Map.drop(["export_json"])
    |> Map.put("export_json_redacted", true)
    |> Map.put("export_json_bytes", byte_size(json))
  end

  defp do_audit_arguments("debugger.reload", %{"source" => source} = args)
       when is_binary(source) do
    args
    |> Map.drop(["source"])
    |> Map.put("source_redacted", true)
    |> Map.put("source_bytes", byte_size(source))
  end

  defp do_audit_arguments(_name, args) when is_map(args), do: args

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

  defp do_call("projects.settings", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug) do
      {:ok, project_settings_payload(project)}
    else
      {:error, reason} -> {:error, "project settings failed: #{inspect(reason)}"}
    end
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

  defp do_call("projects.update_settings", %{"slug" => slug} = args) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, attrs} <- project_settings_update_attrs(project, args),
         {:ok, updated} <- Projects.update_project(project, attrs) do
      {:ok, project_settings_payload(updated)}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "project settings update failed: #{inspect(reason)}"}
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

  defp do_call("files.stat", %{
         "slug" => slug,
         "source_root" => source_root,
         "rel_path" => rel_path
       }) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, absolute_path} <- project_source_file_path(project, source_root, rel_path),
         {:ok, stat} <- File.stat(absolute_path),
         {:ok, content} <- File.read(absolute_path) do
      {:ok,
       %{
         slug: slug,
         source_root: source_root,
         rel_path: rel_path,
         bytes: stat.size,
         mtime: format_file_mtime(stat.mtime),
         sha256: sha256_hex(content)
       }}
    else
      {:error, reason} -> {:error, "stat failed: #{inspect(reason)}"}
    end
  end

  defp do_call("files.read_range", %{
         "slug" => slug,
         "source_root" => source_root,
         "rel_path" => rel_path,
         "offset" => offset,
         "limit" => limit
       }) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, content} <- Projects.read_source_file(project, source_root, rel_path) do
      lines = String.split(content, "\n")
      offset = max(offset, 1)
      limit = clamp_limit(limit)

      selected =
        lines
        |> Enum.drop(offset - 1)
        |> Enum.take(limit)
        |> Enum.with_index(offset)
        |> Enum.map(fn {line, line_number} -> %{line: line_number, text: line} end)

      {:ok,
       %{
         slug: slug,
         source_root: source_root,
         rel_path: rel_path,
         offset: offset,
         limit: limit,
         total_lines: length(lines),
         lines: selected
       }}
    else
      {:error, reason} -> {:error, "read range failed: #{inspect(reason)}"}
    end
  end

  defp do_call("files.search", %{"slug" => slug, "query" => query} = args)
       when is_binary(query) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, roots} <- search_source_roots(project, Map.get(args, "source_root")) do
      limit = args |> Map.get("limit", 50) |> parse_limit()

      matches =
        roots
        |> Enum.flat_map(&search_source_root(project, &1, query))
        |> Enum.take(limit)

      {:ok,
       %{
         slug: slug,
         query: query,
         count: length(matches),
         matches: matches
       }}
    else
      {:error, reason} -> {:error, "search failed: #{inspect(reason)}"}
    end
  end

  defp do_call("projects.diff", %{"slug" => slug} = args) do
    with {:ok, project} <- fetch_project(slug) do
      workspace = Projects.project_workspace_path(project)
      limit_bytes = args |> Map.get("limit_bytes", 50_000) |> parse_diff_limit()

      case System.cmd("git", ["-C", workspace, "diff", "--", "."], stderr_to_stdout: true) do
        {output, exit_code} ->
          truncated? = byte_size(output) > limit_bytes

          {:ok,
           %{
             slug: slug,
             workspace_path: workspace,
             exit_code: exit_code,
             truncated: truncated?,
             diff: binary_part(output, 0, min(byte_size(output), limit_bytes))
           }}
      end
    else
      {:error, reason} -> {:error, "project diff failed: #{inspect(reason)}"}
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

  defp do_call("packages.module_docs", %{"package" => package, "module" => module_name} = args) do
    version = Map.get(args, "version", "latest")

    case Packages.module_doc_markdown(package, version, module_name, []) do
      {:ok, markdown} ->
        {:ok, %{package: package, version: version, module: module_name, markdown: markdown}}

      {:error, reason} ->
        {:error, "packages module docs failed: #{inspect(reason)}"}
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

  defp do_call(
         "files.patch",
         %{
           "slug" => slug,
           "source_root" => source_root,
           "rel_path" => rel_path,
           "old_string" => old_string,
           "new_string" => new_string
         } = args
       ) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, current} <- Projects.read_source_file(project, source_root, rel_path),
         :ok <- validate_expected_sha256(current, Map.get(args, "expected_sha256")),
         {:ok, patched} <- replace_once(current, old_string, new_string),
         :ok <- Projects.write_source_file(project, source_root, rel_path, patched) do
      {:ok,
       %{
         saved: true,
         slug: slug,
         source_root: source_root,
         rel_path: rel_path,
         old_sha256: sha256_hex(current),
         new_sha256: sha256_hex(patched)
       }}
    else
      {:error, reason} -> {:error, "patch failed: #{inspect(reason)}"}
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

  defp do_call("compiler.check_source_root", %{
         "slug" => slug,
         "source_root" => source_root
       }) do
    compiler = compiler_module()

    with {:ok, project} <- fetch_project(slug),
         true <- source_root in project.source_roots,
         {:ok, result} <-
           compiler.check_source_root("#{slug}:#{source_root}",
             workspace_root: Projects.project_workspace_path(project),
             source_root: source_root
           ) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)

      {:ok,
       %{
         slug: slug,
         source_root: source_root,
         status: result.status,
         checked_path: result.checked_path,
         diagnostics: diagnostics,
         error_count: counts.error_count,
         warning_count: counts.warning_count,
         output: result.output
       }}
    else
      false -> {:error, "check source root failed: :invalid_source_root"}
      {:error, reason} -> {:error, "check source root failed: #{inspect(reason)}"}
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

  defp do_call("screenshots.list", %{"slug" => slug}) do
    screenshots = screenshots_module()

    with {:ok, _project} <- fetch_project(slug),
         {:ok, shots} <- screenshots.list(slug, []) do
      entries = Enum.map(shots, &mcp_screenshot_entry/1)

      {:ok,
       %{
         slug: slug,
         count: length(entries),
         screenshots: entries
       }}
    else
      {:error, reason} -> {:error, "screenshot list failed: #{inspect(reason)}"}
    end
  end

  defp do_call("screenshots.read", %{
         "slug" => slug,
         "emulator_target" => emulator_target,
         "filename" => filename
       }) do
    screenshots = screenshots_module()

    with {:ok, _project} <- fetch_project(slug),
         {:ok, shots} <- screenshots.list(slug, []),
         {:ok, shot} <- find_screenshot(shots, emulator_target, filename),
         {:ok, data} <- File.read(Map.fetch!(shot, :absolute_path)) do
      metadata = mcp_screenshot_entry(shot)

      {:ok,
       %{
         slug: slug,
         screenshot: metadata,
         mime_type: metadata.mime_type,
         encoding: "base64",
         bytes: byte_size(data),
         sha256: Base.encode16(:crypto.hash(:sha256, data), case: :lower),
         content_base64: Base.encode64(data)
       }}
    else
      {:error, reason} -> {:error, "screenshot read failed: #{inspect(reason)}"}
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
           compiler.compile(slug, workspace_root: Projects.project_workspace_path(project)),
         :ok <- ingest_compile_result(slug, project, result) do
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

  defp do_call("publish.prepare", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, package} <- package_for_publish(project),
         {:ok, context} <- publish_context(project, package),
         {:ok, manifest} <-
           PublishManifest.export(slug,
             artifact_path: package.artifact_path,
             screenshot_groups: context.screenshot_groups,
             required_targets: context.required_targets,
             readiness: context.readiness
           ),
         {:ok, release_notes} <-
           PublishManifest.export_release_notes(slug, context.validation.release_notes_md) do
      {:ok,
       %{
         slug: slug,
         status: context.validation.status,
         artifact_path: package.artifact_path,
         app_root: package.app_root,
         required_targets: context.required_targets,
         readiness: context.readiness,
         checks: context.validation.checks,
         manifest_path: manifest.path,
         release_notes_path: release_notes.path,
         release_notes_md: context.validation.release_notes_md,
         build_result: package.build_result
       }}
    else
      {:error, reason} -> {:error, "publish prepare failed: #{inspect(reason)}"}
    end
  end

  defp do_call("publish.validate", %{"slug" => slug} = args) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, package} <- resolve_publish_validation_package(project, args),
         {:ok, context} <- publish_context(project, package) do
      {:ok,
       %{
         slug: slug,
         status: context.validation.status,
         artifact_path: package.artifact_path,
         app_root: package.app_root,
         required_targets: context.required_targets,
         readiness: context.readiness,
         checks: context.validation.checks,
         release_notes_md: context.validation.release_notes_md,
         build_result: Map.get(package, :build_result)
       }}
    else
      {:error, reason} -> {:error, "publish validate failed: #{inspect(reason)}"}
    end
  end

  defp do_call("publish.submit", %{"slug" => slug} = args) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, package} <- resolve_publish_submit_package(project, args),
         {:ok, context} <- publish_context(project, package),
         :ok <- ensure_publish_ready(context.validation),
         release_notes <- publish_submit_release_notes(args),
         {:ok, screenshot_paths} <-
           PublishFlow.stage_publish_screenshots(package.app_root, context.screenshot_groups),
         {:ok, result} <-
           app_store_publisher_module().publish(project,
             app_root: package.app_root,
             artifact_path: package.artifact_path,
             release_notes: release_notes || "",
             version: Map.get(args, "version") || publish_version(project),
             description: Map.get(args, "description") || publish_description(project),
             screenshots: screenshot_paths,
             is_published: Map.get(args, "is_published", true) == true,
             all_platforms: Map.get(args, "all_platforms", false) == true,
             gif_all_platforms: Map.get(args, "gif_all_platforms", false) == true,
             firebase_id_token: Map.get(args, "firebase_id_token"),
             store_icons:
               Ide.StoreAssets.publish_icon_paths(Projects.project_workspace_path(project))
           ) do
      {:ok,
       %{
         slug: slug,
         status: result.status,
         command: result.command,
         exit_code: result.exit_code,
         cwd: result.cwd,
         output: result.output,
         artifact_path: package.artifact_path,
         app_root: package.app_root,
         readiness: context.readiness,
         checks: context.validation.checks
       }}
    else
      {:error, reason} -> {:error, "publish submit failed: #{inspect(reason)}"}
    end
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

  defp do_call("debugger.render_tree", %{"slug" => slug} = args) do
    target = Map.get(args, "target", "watch")
    include_tree? = truthy?(Map.get(args, "include_tree"))

    with {:ok, target_atom} <- parse_render_tree_target(target),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 1),
         {:ok, runtime} <- debugger_surface_runtime(state, target_atom),
         %{} = tree <- DebuggerSupport.rendered_tree(runtime) do
      screen = debugger_surface_screen(state, runtime, target_atom)
      nodes = flatten_rendered_nodes(tree, screen.width, screen.height)

      payload = %{
        slug: slug,
        target: Atom.to_string(target_atom),
        screen: screen,
        root_type: rendered_node_type(tree),
        node_count: length(nodes),
        nodes: nodes
      }

      {:ok, if(include_tree?, do: Map.put(payload, :tree, tree), else: payload)}
    else
      {:ok, nil} -> {:error, "debugger render_tree failed: :no_rendered_tree"}
      nil -> {:error, "debugger render_tree failed: :no_rendered_tree"}
      {:error, reason} -> {:error, "debugger render_tree failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.preview_diagnostics", %{"slug" => slug} = args) do
    target = Map.get(args, "target", "watch")
    event_limit = parse_event_limit(Map.get(args, "event_limit", 100))

    with {:ok, target_atom} <- parse_render_tree_target(target),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: event_limit),
         {:ok, runtime} <- debugger_surface_runtime(state, target_atom) do
      events = Map.get(state, :events) || []
      cursor_seq = resolve_cursor_seq(events, nil)
      runtime_fingerprints = DebuggerSupport.runtime_fingerprints_at_cursor(events, cursor_seq)
      screen = debugger_surface_screen(state, runtime || %{}, target_atom)

      {:ok,
       preview_diagnostics_payload(
         slug,
         state,
         runtime || %{},
         target_atom,
         screen,
         runtime_fingerprints,
         events,
         cursor_seq
       )}
    else
      {:error, reason} -> {:error, "debugger preview diagnostics failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.models", %{"slug" => slug} = args) do
    include_view_output? = truthy?(Map.get(args, "include_view_output"))

    with {:ok, targets} <- parse_optional_debugger_targets(Map.get(args, "target")),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 1) do
      models =
        targets
        |> Enum.map(fn target ->
          {target, surface_model_payload(state, target, include_view_output?)}
        end)
        |> Map.new()

      {:ok,
       %{
         slug: slug,
         seq: Map.get(state, :seq),
         running: Map.get(state, :running, false),
         revision: Map.get(state, :revision),
         watch_profile_id: Map.get(state, :watch_profile_id),
         models: models
       }}
    else
      {:error, reason} -> {:error, "debugger models failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.timeline", %{"slug" => slug} = args) do
    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <-
           Debugger.snapshot(slug,
             event_limit: parse_event_limit(args["event_limit"]),
             since_seq: parse_since_seq(args["since_seq"]),
             types: parse_event_types(args["types"])
           ) do
      events = Map.get(state, :events) || []

      {:ok,
       %{
         slug: slug,
         seq: Map.get(state, :seq),
         count: length(events),
         timeline: Enum.map(events, &compact_debugger_event/1)
       }}
    else
      {:error, reason} -> {:error, "debugger timeline failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.surface_state", %{"slug" => slug} = args) do
    target = Map.get(args, "target", "watch")
    include_view_output? = truthy?(Map.get(args, "include_view_output"))
    include_render_tree? = truthy?(Map.get(args, "include_render_tree"))

    with {:ok, target_atom} <- parse_render_tree_target(target),
         {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 100),
         {:ok, runtime} <- debugger_surface_runtime(state, target_atom) do
      events = Map.get(state, :events) || []
      screen = debugger_surface_screen(state, runtime, target_atom)
      render_tree = maybe_render_tree_payload(runtime, screen, include_render_tree?)

      {:ok,
       %{
         slug: slug,
         seq: Map.get(state, :seq),
         target: Atom.to_string(target_atom),
         screen: screen,
         model: surface_model_payload(state, target_atom, include_view_output?),
         last_message: map_get_any(runtime, [:last_message, "last_message"], nil),
         protocol_messages: map_get_any(runtime, [:protocol_messages, "protocol_messages"], []),
         runtime_fingerprint:
           events
           |> DebuggerSupport.runtime_fingerprints_at_cursor(nil)
           |> Map.get(target_atom),
         render_tree: render_tree
       }}
    else
      {:error, reason} -> {:error, "debugger surface_state failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.watch_profiles", _args) do
    {:ok, %{watch_profiles: Debugger.watch_profiles()}}
  end

  defp do_call("debugger.simulator_settings", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 1) do
      persisted = project_simulator_settings(project)
      active = Map.get(state, :simulator_settings) || persisted
      {:ok, %{slug: slug, settings: active, persisted_settings: persisted}}
    else
      {:error, reason} -> {:error, "debugger simulator settings failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.configuration", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 1) do
      settings = project.debugger_settings || %{}
      persisted_values = map_value(settings, "configuration_values") || %{}
      companion_model = get_in(state, [:companion, :model]) || %{}

      configuration =
        map_value(companion_model, "configuration") ||
          get_in(companion_model, ["runtime_model", "configuration"]) ||
          %{}

      {:ok,
       %{
         slug: slug,
         values: persisted_values,
         configuration: configuration
       }}
    else
      {:error, reason} -> {:error, "debugger configuration failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.auto_fire", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 1) do
      settings = project.debugger_settings || %{}

      {:ok,
       %{
         slug: slug,
         auto_fire: map_value(settings, "auto_fire") || %{},
         auto_fire_subscriptions: map_value(settings, "auto_fire_subscriptions") || [],
         runtime_auto_tick: Map.get(state, :auto_tick) || %{}
       }}
    else
      {:error, reason} -> {:error, "debugger auto_fire failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.disabled_subscriptions", %{"slug" => slug}) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 1) do
      settings = project.debugger_settings || %{}

      {:ok,
       %{
         slug: slug,
         disabled_subscriptions: map_value(settings, "disabled_subscriptions") || [],
         runtime_disabled_subscriptions: Map.get(state, :disabled_subscriptions) || []
       }}
    else
      {:error, reason} -> {:error, "debugger disabled_subscriptions failed: #{inspect(reason)}"}
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

  defp do_call(
         "debugger.set_watch_profile",
         %{
           "slug" => slug,
           "watch_profile_id" => watch_profile_id
         } = args
       ) do
    attrs = %{
      watch_profile_id: watch_profile_id,
      launch_reason: Map.get(args, "launch_reason")
    }

    with {:ok, _project} <- fetch_project(slug),
         {:ok, state} <- Debugger.set_watch_profile(slug, attrs) do
      {:ok, %{slug: slug, state: state}}
    else
      {:error, reason} -> {:error, "debugger set_watch_profile failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.set_simulator_settings", %{"slug" => slug, "settings" => settings})
       when is_map(settings) do
    with {:ok, project} <- fetch_project(slug),
         normalized <- normalize_mcp_simulator_settings(settings),
         {:ok, _project} <- persist_project_debugger_setting(project, "simulator", normalized),
         {:ok, state} <- Debugger.set_simulator_settings(slug, normalized) do
      {:ok, %{slug: slug, settings: normalized, state: state}}
    else
      {:error, reason} -> {:error, "debugger set_simulator_settings failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.save_configuration", %{"slug" => slug, "values" => values})
       when is_map(values) do
    with {:ok, project} <- fetch_project(slug),
         values <- normalize_configuration_values(values),
         {:ok, _project} <-
           persist_project_debugger_setting(project, "configuration_values", values),
         {:ok, state} <- Debugger.save_configuration(slug, values) do
      {:ok, %{slug: slug, values: values, state: state}}
    else
      {:error, reason} -> {:error, "debugger save_configuration failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.set_auto_fire", %{"slug" => slug} = args) do
    attrs = %{
      target: map_value(args, "target"),
      trigger: map_value(args, "trigger"),
      enabled: map_value(args, "enabled")
    }

    with {:ok, project} <- fetch_project(slug),
         {:ok, project} <- persist_project_auto_fire_setting(project, attrs),
         {:ok, state} <- Debugger.set_auto_fire(slug, attrs) do
      settings = project.debugger_settings || %{}

      {:ok,
       %{
         slug: slug,
         auto_fire: map_value(settings, "auto_fire") || %{},
         auto_fire_subscriptions: map_value(settings, "auto_fire_subscriptions") || [],
         state: state
       }}
    else
      {:error, reason} -> {:error, "debugger set_auto_fire failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.set_subscription_enabled", %{"slug" => slug} = args) do
    attrs = %{
      target: map_value(args, "target"),
      trigger: map_value(args, "trigger"),
      enabled: map_value(args, "enabled")
    }

    with {:ok, project} <- fetch_project(slug),
         {:ok, project} <- persist_project_disabled_subscription_setting(project, attrs),
         {:ok, state} <- Debugger.set_subscription_enabled(slug, attrs) do
      settings = project.debugger_settings || %{}

      {:ok,
       %{
         slug: slug,
         disabled_subscriptions: map_value(settings, "disabled_subscriptions") || [],
         state: state
       }}
    else
      {:error, reason} ->
        {:error, "debugger set_subscription_enabled failed: #{inspect(reason)}"}
    end
  end

  defp do_call("debugger.reload", %{"slug" => slug, "rel_path" => rel_path} = args)
       when is_binary(rel_path) do
    reason = Map.get(args, "reason") || "mcp_reload"
    source_root = Map.get(args, "source_root") || "watch"

    with {:ok, project} <- fetch_project(slug),
         {:ok, source} <-
           debugger_reload_source(project, source_root, rel_path, Map.get(args, "source")),
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
            screenshot_count: screenshot_count(project),
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
            screenshots_count: screenshot_count(project)
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

  @spec project_settings_payload(map()) :: map()
  defp project_settings_payload(project) when is_map(project) do
    %{
      name: Map.get(project, :name),
      slug: Map.get(project, :slug),
      target_type: Map.get(project, :target_type),
      source_roots: Map.get(project, :source_roots) || [],
      active: Map.get(project, :active) == true,
      release_defaults: Map.get(project, :release_defaults) || %{},
      github: safe_github_settings(Map.get(project, :github) || %{}),
      debugger: safe_debugger_settings(Map.get(project, :debugger_settings) || %{})
    }
  end

  @spec project_settings_update_attrs(map(), map()) :: {:ok, map()} | {:error, String.t()}
  defp project_settings_update_attrs(project, args) when is_map(project) and is_map(args) do
    attrs =
      %{}
      |> maybe_put_string_setting(args, "name")
      |> maybe_put_inclusion_setting(args, "target_type", ~w(app watchface companion))
      |> maybe_put_boolean_setting(args, "active")

    attrs =
      case map_value(args, "release_defaults") do
        release_defaults when is_map(release_defaults) ->
          current = Map.get(project, :release_defaults) || %{}

          Map.put(
            attrs,
            "release_defaults",
            Map.merge(current, safe_release_defaults(release_defaults))
          )

        _ ->
          attrs
      end

    attrs =
      case map_value(args, "github") do
        github when is_map(github) ->
          current = Map.get(project, :github) || %{}
          Map.put(attrs, "github", Map.merge(current, safe_github_settings(github)))

        _ ->
          attrs
      end

    attrs =
      case map_value(args, "debugger") do
        debugger when is_map(debugger) ->
          settings =
            (Map.get(project, :debugger_settings) || %{})
            |> Map.merge(safe_debugger_settings_update(debugger))

          Map.put(attrs, "debugger_settings", settings)

        _ ->
          attrs
      end

    {:ok, attrs}
  end

  @spec safe_release_defaults(term()) :: map()
  defp safe_release_defaults(map) when is_map(map) do
    %{}
    |> maybe_put_string_setting(map, "version_label")
    |> maybe_put_string_setting(map, "tags")
    |> maybe_put_string_list_setting(map, "target_platforms")
    |> maybe_put_string_list_setting(map, "capabilities")
  end

  defp safe_release_defaults(_), do: %{}

  @spec safe_github_settings(term()) :: map()
  defp safe_github_settings(map) when is_map(map) do
    visibility =
      map
      |> Map.get("visibility", Map.get(map, :visibility))
      |> then(fn
        v when v in ["private", "public"] -> v
        _ -> nil
      end)

    github =
      %{}
      |> maybe_put_string_setting(map, "owner")
      |> maybe_put_string_setting(map, "repo")
      |> maybe_put_string_setting(map, "branch")

    case visibility do
      nil -> github
      v -> Map.put(github, "visibility", v)
    end
  end

  defp safe_github_settings(_), do: %{}

  @spec safe_debugger_settings(term()) :: map()
  defp safe_debugger_settings(map) when is_map(map) do
    %{}
    |> maybe_put_existing(map, "timeline_mode")
    |> maybe_put_existing(map, "watch_profile_id")
    |> maybe_put_existing(map, "emulator_target")
    |> maybe_put_existing(map, "emulator_mode")
    |> maybe_put_existing(map, "configuration_values")
    |> maybe_put_existing(map, "auto_fire")
    |> maybe_put_existing(map, "auto_fire_subscriptions")
    |> maybe_put_existing(map, "disabled_subscriptions")
    |> Map.put("simulator", normalize_mcp_simulator_settings(map_value(map, "simulator") || %{}))
  end

  defp safe_debugger_settings(_), do: %{"simulator" => Debugger.default_simulator_settings()}

  @spec safe_debugger_settings_update(term()) :: map()
  defp safe_debugger_settings_update(map) when is_map(map) do
    %{}
    |> maybe_put_inclusion_setting(map, "timeline_mode", ~w(watch companion mixed separate))
    |> maybe_put_string_setting(map, "watch_profile_id")
    |> maybe_put_string_setting(map, "emulator_target")
    |> maybe_put_inclusion_setting(map, "emulator_mode", EmulatorSupport.allowed_mode_ids())
  end

  defp safe_debugger_settings_update(_), do: %{}

  defp patch_emulator_mode_tool_schemas(tools) do
    modes = EmulatorSupport.allowed_mode_ids()

    Enum.map(tools, fn
      %{name: "projects.update_settings"} = tool ->
        update_in(
          tool,
          [:inputSchema, :properties, :debugger, :properties, :emulator_mode, :enum],
          fn _ -> modes end
        )

      tool ->
        tool
    end)
  end

  @spec project_simulator_settings(map()) :: map()
  defp project_simulator_settings(project) when is_map(project) do
    project
    |> Map.get(:debugger_settings, %{})
    |> map_value("simulator")
    |> normalize_mcp_simulator_settings()
  end

  @spec normalize_mcp_simulator_settings(term()) :: map()
  defp normalize_mcp_simulator_settings(settings) when is_map(settings) do
    defaults = Debugger.default_simulator_settings()

    %{
      "battery_percent" =>
        settings
        |> map_value("battery_percent")
        |> normalize_mcp_integer(defaults["battery_percent"], 0, 100),
      "charging" =>
        settings
        |> map_value("charging")
        |> normalize_mcp_boolean(defaults["charging"]),
      "connected" =>
        settings
        |> map_value("connected")
        |> normalize_mcp_boolean(defaults["connected"]),
      "clock_24h" =>
        settings
        |> map_value("clock_24h")
        |> normalize_mcp_boolean(defaults["clock_24h"]),
      "use_simulated_time" =>
        settings
        |> map_value("use_simulated_time")
        |> normalize_mcp_boolean(defaults["use_simulated_time"]),
      "simulated_time" =>
        settings
        |> map_value("simulated_time")
        |> normalize_mcp_optional_string(defaults["simulated_time"]),
      "simulated_date" =>
        settings
        |> map_value("simulated_date")
        |> normalize_mcp_optional_string(defaults["simulated_date"]),
      "latitude" =>
        settings
        |> map_value("latitude")
        |> normalize_mcp_float(defaults["latitude"], -90.0, 90.0),
      "longitude" =>
        settings
        |> map_value("longitude")
        |> normalize_mcp_float(defaults["longitude"], -180.0, 180.0),
      "accuracy" =>
        settings
        |> map_value("accuracy")
        |> normalize_mcp_float(defaults["accuracy"], 0.0, 100_000.0)
    }
  end

  defp normalize_mcp_simulator_settings(_settings), do: Debugger.default_simulator_settings()

  @spec normalize_configuration_values(map()) :: map()
  defp normalize_configuration_values(values) when is_map(values) do
    Map.new(values, fn
      {key, list} when is_list(list) -> {to_string(key), List.last(list)}
      {key, value} -> {to_string(key), value}
    end)
  end

  @spec persist_project_debugger_setting(map(), String.t(), term()) ::
          {:ok, map()} | {:error, term()}
  defp persist_project_debugger_setting(project, key, value)
       when is_map(project) and is_binary(key) do
    settings =
      project
      |> Map.get(:debugger_settings, %{})
      |> Map.put(key, value)

    Projects.update_project(project, %{"debugger_settings" => settings})
  end

  @spec persist_project_auto_fire_setting(map(), map()) :: {:ok, map()} | {:error, term()}
  defp persist_project_auto_fire_setting(project, attrs) when is_map(project) and is_map(attrs) do
    target = debugger_setting_target(map_value(attrs, "target"))
    trigger = map_value(attrs, "trigger")
    enabled? = normalize_mcp_boolean(map_value(attrs, "enabled"), false)
    settings = Map.get(project, :debugger_settings) || %{}

    updated_settings =
      if is_binary(trigger) and String.trim(trigger) != "" do
        subscriptions =
          settings
          |> map_value("auto_fire_subscriptions")
          |> update_project_auto_fire_subscriptions(target, trigger, enabled?)

        auto_fire = map_value(settings, "auto_fire") || %{}

        settings
        |> Map.put("auto_fire", Map.put(auto_fire, target, false))
        |> Map.put("auto_fire_subscriptions", subscriptions)
      else
        auto_fire = map_value(settings, "auto_fire") || %{}
        Map.put(settings, "auto_fire", Map.put(auto_fire, target, enabled?))
      end

    Projects.update_project(project, %{"debugger_settings" => updated_settings})
  end

  @spec persist_project_disabled_subscription_setting(map(), map()) ::
          {:ok, map()} | {:error, term()}
  defp persist_project_disabled_subscription_setting(project, attrs)
       when is_map(project) and is_map(attrs) do
    target = debugger_setting_target(map_value(attrs, "target"))
    trigger = map_value(attrs, "trigger")
    enabled? = normalize_mcp_boolean(map_value(attrs, "enabled"), false)
    settings = Map.get(project, :debugger_settings) || %{}

    disabled_subscriptions =
      settings
      |> map_value("disabled_subscriptions")
      |> update_project_disabled_subscriptions(target, trigger, enabled?)

    Projects.update_project(project, %{
      "debugger_settings" => Map.put(settings, "disabled_subscriptions", disabled_subscriptions)
    })
  end

  @spec update_project_auto_fire_subscriptions(term(), term(), term(), boolean()) :: [map()]
  defp update_project_auto_fire_subscriptions(subscriptions, target, trigger, enabled?) do
    trigger = String.trim(to_string(trigger))

    subscriptions =
      subscriptions
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.reject(&(map_value(&1, "target") == target and map_value(&1, "trigger") == trigger))

    if enabled? and trigger != "" do
      [%{"target" => target, "trigger" => trigger} | subscriptions]
    else
      subscriptions
    end
    |> Enum.uniq_by(&{map_value(&1, "target"), map_value(&1, "trigger")})
  end

  @spec update_project_disabled_subscriptions(term(), term(), term(), boolean()) :: [map()]
  defp update_project_disabled_subscriptions(subscriptions, target, trigger, enabled?)
       when is_binary(trigger) and trigger != "" do
    trigger = String.trim(trigger)

    subscriptions =
      subscriptions
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.reject(&(map_value(&1, "target") == target and map_value(&1, "trigger") == trigger))

    if enabled? do
      subscriptions
    else
      [%{"target" => target, "trigger" => trigger} | subscriptions]
    end
    |> Enum.uniq_by(&{map_value(&1, "target"), map_value(&1, "trigger")})
  end

  defp update_project_disabled_subscriptions(subscriptions, _target, _trigger, _enabled?),
    do: subscriptions |> List.wrap() |> Enum.filter(&is_map/1)

  @spec debugger_setting_target(term()) :: String.t()
  defp debugger_setting_target("protocol"), do: "protocol"
  defp debugger_setting_target("companion"), do: "phone"
  defp debugger_setting_target("phone"), do: "phone"
  defp debugger_setting_target(:protocol), do: "protocol"
  defp debugger_setting_target(:companion), do: "phone"
  defp debugger_setting_target(:phone), do: "phone"
  defp debugger_setting_target(_target), do: "watch"

  defp package_for_publish(project) do
    toolchain = pebble_toolchain_module()

    toolchain.package(project.slug,
      workspace_root: Projects.project_workspace_path(project),
      target_type: project.target_type,
      project_name: project.name,
      target_platforms: publish_target_platforms(project),
      version: publish_version(project),
      description: publish_description(project),
      capabilities: publish_capabilities(project)
    )
  end

  defp resolve_publish_validation_package(_project, %{"package" => false} = args) do
    {:ok,
     %{
       status: :unknown,
       artifact_path: Map.get(args, "artifact_path"),
       app_root: Map.get(args, "app_root"),
       build_result: nil
     }}
  end

  defp resolve_publish_validation_package(project, _args), do: package_for_publish(project)

  defp resolve_publish_submit_package(_project, %{"app_root" => app_root} = args)
       when is_binary(app_root) and app_root != "" do
    {:ok,
     %{
       status: :unknown,
       artifact_path: Map.get(args, "artifact_path"),
       app_root: app_root,
       build_result: nil
     }}
  end

  defp resolve_publish_submit_package(project, _args), do: package_for_publish(project)

  defp publish_context(project, package) do
    screenshots = screenshots_module()
    required_targets = publish_target_platforms(project)

    with {:ok, shots} <- screenshots.list(project.slug, []),
         readiness <- publish_readiness(shots, required_targets),
         screenshot_groups <- group_publish_screenshots(shots),
         {:ok, validation} <-
           PublishReadiness.validate(
             artifact_path: package.artifact_path,
             required_targets: required_targets,
             readiness: readiness,
             app_root: package.app_root,
             project_slug: project.slug
           ) do
      {:ok,
       %{
         required_targets: required_targets,
         readiness: readiness,
         screenshot_groups: screenshot_groups,
         validation: validation
       }}
    end
  end

  defp publish_readiness(shots, targets) do
    counts =
      shots
      |> Enum.group_by(& &1.emulator_target)
      |> Map.new(fn {target, values} -> {target, length(values)} end)

    Enum.map(targets, fn target ->
      count = Map.get(counts, target, 0)
      %{target: target, count: count, status: if(count > 0, do: :ok, else: :missing)}
    end)
  end

  defp group_publish_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {target, _shots} -> target end)
  end

  defp ensure_publish_ready(%{status: :ok}), do: :ok
  defp ensure_publish_ready(validation), do: {:error, {:publish_not_ready, validation.checks}}

  defp publish_target_platforms(project) do
    defaults = Map.get(project, :release_defaults) || %{}
    allowed = PebbleToolchain.supported_emulator_targets()
    allowed_set = MapSet.new(allowed)

    defaults
    |> Map.get("target_platforms", allowed)
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed_set, &1))
    |> Enum.uniq()
    |> case do
      [] -> allowed
      targets -> targets
    end
  end

  defp publish_capabilities(project) do
    defaults = Map.get(project, :release_defaults) || %{}

    defaults
    |> Map.get("capabilities", [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp publish_version(project) do
    project
    |> publish_defaults()
    |> Map.get("version_label", "")
    |> to_string()
    |> String.trim()
  end

  defp publish_description(project) do
    project
    |> publish_defaults()
    |> Map.get("description", "")
    |> to_string()
    |> String.trim()
  end

  defp publish_submit_release_notes(args) when is_map(args) do
    case Map.get(args, "release_notes") do
      notes when is_binary(notes) -> String.trim(notes)
      _ -> ""
    end
  end

  defp publish_defaults(project), do: Map.get(project, :release_defaults) || %{}

  @spec fetch_project(String.t()) :: {:ok, map()} | {:error, :project_not_found}
  defp fetch_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  @spec authorized?(String.t(), [capability()]) :: boolean()
  defp authorized?("projects.list", capabilities), do: :read in capabilities
  defp authorized?("projects.settings", capabilities), do: :read in capabilities
  defp authorized?("projects.tree", capabilities), do: :read in capabilities
  defp authorized?("files.read", capabilities), do: :read in capabilities
  defp authorized?("files.stat", capabilities), do: :read in capabilities
  defp authorized?("files.read_range", capabilities), do: :read in capabilities
  defp authorized?("files.search", capabilities), do: :read in capabilities
  defp authorized?("projects.diff", capabilities), do: :read in capabilities
  defp authorized?("screenshots.list", capabilities), do: :read in capabilities
  defp authorized?("screenshots.read", capabilities), do: :read in capabilities
  defp authorized?("packages.search", capabilities), do: :read in capabilities
  defp authorized?("packages.details", capabilities), do: :read in capabilities
  defp authorized?("packages.versions", capabilities), do: :read in capabilities
  defp authorized?("packages.readme", capabilities), do: :read in capabilities
  defp authorized?("packages.module_docs", capabilities), do: :read in capabilities
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
  defp authorized?("debugger.render_tree", capabilities), do: :read in capabilities
  defp authorized?("debugger.preview_diagnostics", capabilities), do: :read in capabilities
  defp authorized?("debugger.models", capabilities), do: :read in capabilities
  defp authorized?("debugger.timeline", capabilities), do: :read in capabilities
  defp authorized?("debugger.surface_state", capabilities), do: :read in capabilities
  defp authorized?("debugger.simulator_settings", capabilities), do: :read in capabilities
  defp authorized?("debugger.configuration", capabilities), do: :read in capabilities
  defp authorized?("debugger.auto_fire", capabilities), do: :read in capabilities
  defp authorized?("debugger.disabled_subscriptions", capabilities), do: :read in capabilities
  defp authorized?("debugger.watch_profiles", capabilities), do: :read in capabilities
  defp authorized?("projects.create", capabilities), do: :edit in capabilities
  defp authorized?("projects.delete", capabilities), do: :edit in capabilities
  defp authorized?("projects.update_settings", capabilities), do: :edit in capabilities
  defp authorized?("files.write", capabilities), do: :edit in capabilities
  defp authorized?("files.patch", capabilities), do: :edit in capabilities
  defp authorized?("packages.add_to_elm_json", capabilities), do: :edit in capabilities
  defp authorized?("packages.remove_from_elm_json", capabilities), do: :edit in capabilities
  defp authorized?("traces.export_write", capabilities), do: :edit in capabilities
  defp authorized?("traces.exports_prune", capabilities), do: :edit in capabilities
  defp authorized?("traces.maintenance", capabilities), do: :edit in capabilities
  defp authorized?("debugger.start", capabilities), do: :edit in capabilities
  defp authorized?("debugger.reset", capabilities), do: :edit in capabilities
  defp authorized?("debugger.set_watch_profile", capabilities), do: :edit in capabilities
  defp authorized?("debugger.set_simulator_settings", capabilities), do: :edit in capabilities
  defp authorized?("debugger.save_configuration", capabilities), do: :edit in capabilities
  defp authorized?("debugger.set_auto_fire", capabilities), do: :edit in capabilities
  defp authorized?("debugger.set_subscription_enabled", capabilities), do: :edit in capabilities
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
  defp authorized?("compiler.check_source_root", capabilities), do: :build in capabilities
  defp authorized?("compiler.compile", capabilities), do: :build in capabilities
  defp authorized?("compiler.manifest", capabilities), do: :build in capabilities
  defp authorized?("publish.prepare", capabilities), do: :build in capabilities
  defp authorized?("publish.validate", capabilities), do: :build in capabilities
  defp authorized?("publish.submit", capabilities), do: :publish in capabilities
  defp authorized?(_, _), do: false

  @spec add_if(list(), boolean(), list()) :: list()
  defp add_if(list, true, entries), do: list ++ entries
  defp add_if(list, false, _entries), do: list

  @spec publish_tool_name(map()) :: map()
  defp publish_tool_name(%{name: name} = tool) when is_binary(name) do
    %{tool | name: Map.fetch!(@public_tool_names_by_internal, name)}
  end

  @spec internal_tool_name(String.t()) :: String.t()
  defp internal_tool_name(name) when is_binary(name) do
    cond do
      MapSet.member?(@internal_tool_names, name) -> name
      internal = Map.get(@internal_tool_names_by_public, name) -> internal
      true -> name
    end
  end

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

  @spec map_value(map(), String.t()) :: term()
  defp map_value(map, key) when is_map(map) and is_binary(key),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  defp map_value(_map, _key), do: nil

  @spec maybe_put_existing(map(), map(), String.t()) :: map()
  defp maybe_put_existing(acc, source, key) when is_map(source) do
    case map_value(source, key) do
      nil -> acc
      value -> Map.put(acc, key, value)
    end
  end

  @spec maybe_put_string_setting(map(), map(), String.t()) :: map()
  defp maybe_put_string_setting(acc, source, key) when is_map(source) do
    case map_value(source, key) do
      value when is_binary(value) -> Map.put(acc, key, String.trim(value))
      _ -> acc
    end
  end

  @spec maybe_put_string_list_setting(map(), map(), String.t()) :: map()
  defp maybe_put_string_list_setting(acc, source, key) when is_map(source) do
    case map_value(source, key) do
      values when is_list(values) ->
        values =
          values
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(acc, key, values)

      _ ->
        acc
    end
  end

  @spec maybe_put_boolean_setting(map(), map(), String.t()) :: map()
  defp maybe_put_boolean_setting(acc, source, key) when is_map(source) do
    case map_value(source, key) do
      nil -> acc
      value -> Map.put(acc, key, normalize_mcp_boolean(value, false))
    end
  end

  @spec maybe_put_inclusion_setting(map(), map(), String.t(), [String.t()]) :: map()
  defp maybe_put_inclusion_setting(acc, source, key, allowed) when is_map(source) do
    case map_value(source, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value in allowed do
          Map.put(acc, key, value)
        else
          acc
        end

      _ ->
        acc
    end
  end

  @spec normalize_mcp_integer(term(), integer(), integer(), integer()) :: integer()
  defp normalize_mcp_integer(value, _default, min, max) when is_integer(value),
    do: value |> Kernel.max(min) |> Kernel.min(max)

  defp normalize_mcp_integer(value, default, min, max) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> normalize_mcp_integer(parsed, default, min, max)
      :error -> default
    end
  end

  defp normalize_mcp_integer(_value, default, _min, _max), do: default

  @spec normalize_mcp_float(term(), float(), float(), float()) :: float()
  defp normalize_mcp_float(value, _default, min, max) when is_float(value),
    do: value |> Kernel.max(min) |> Kernel.min(max)

  defp normalize_mcp_float(value, _default, min, max) when is_integer(value),
    do: (value * 1.0) |> Kernel.max(min) |> Kernel.min(max)

  defp normalize_mcp_float(value, default, min, max) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> normalize_mcp_float(parsed, default, min, max)
      :error -> default
    end
  end

  defp normalize_mcp_float(_value, default, _min, _max), do: default

  @spec normalize_mcp_optional_string(term(), String.t() | nil) :: String.t() | nil
  defp normalize_mcp_optional_string(value, _default) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_mcp_optional_string(_value, default), do: default

  @spec normalize_mcp_boolean(term(), boolean()) :: boolean()
  defp normalize_mcp_boolean(value, _default) when value in [true, "true", "on", "1", 1],
    do: true

  defp normalize_mcp_boolean(value, _default) when value in [false, "false", "off", "0", 0],
    do: false

  defp normalize_mcp_boolean([value | _], default), do: normalize_mcp_boolean(value, default)
  defp normalize_mcp_boolean(_value, default), do: default

  @spec redact_patch_argument(map(), String.t()) :: map()
  defp redact_patch_argument(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) ->
        args
        |> Map.delete(key)
        |> Map.put("#{key}_redacted", true)
        |> Map.put("#{key}_bytes", byte_size(value))

      _other ->
        args
    end
  end

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

  @spec screenshot_count(term()) :: non_neg_integer()
  defp screenshot_count(%Projects.Project{} = project) do
    case Screenshots.list(project, []) do
      {:ok, shots} -> length(shots)
      {:error, _reason} -> 0
    end
  end

  defp screenshot_count(project_slug) when is_binary(project_slug) do
    case Screenshots.list(project_slug, []) do
      {:ok, shots} -> length(shots)
      {:error, _reason} -> 0
    end
  end

  @spec ingest_compile_result(String.t(), map(), map()) :: :ok
  defp ingest_compile_result(slug, project, result)
       when is_binary(slug) and is_map(result) do
    attrs =
      result
      |> Map.put_new(:source_root, compile_result_source_root(project, result))

    case Debugger.ingest_elmc_compile(slug, attrs) do
      {:ok, _state} -> :ok
      _ -> :ok
    end
  end

  defp ingest_compile_result(_slug, _project, _result), do: :ok

  @spec compile_result_source_root(map(), map()) :: String.t()
  defp compile_result_source_root(project, result) when is_map(result) do
    workspace = Projects.project_workspace_path(project)
    compiled_path = Map.get(result, :compiled_path) || Map.get(result, "compiled_path")

    with path when is_binary(path) <- compiled_path,
         relative when relative != path <- Path.relative_to(path, workspace),
         [source_root | _] <- Path.split(relative),
         true <- source_root in project.source_roots do
      source_root
    else
      _ -> List.first(project.source_roots) || "watch"
    end
  end

  @spec project_source_file_path(map(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  defp project_source_file_path(project, source_root, rel_path)
       when is_binary(source_root) and is_binary(rel_path) do
    if source_root in project.source_roots do
      source_base = Path.join(Projects.project_workspace_path(project), source_root)
      expanded = Path.expand(rel_path, source_base)
      allowed_prefix = source_base <> "/"

      cond do
        expanded == source_base -> {:error, :invalid_path}
        String.starts_with?(expanded, allowed_prefix) -> {:ok, expanded}
        true -> {:error, :invalid_path}
      end
    else
      {:error, :invalid_source_root}
    end
  end

  defp project_source_file_path(_project, _source_root, _rel_path), do: {:error, :invalid_path}

  @spec format_file_mtime(:calendar.datetime()) :: String.t()
  defp format_file_mtime(mtime) do
    case NaiveDateTime.from_erl(mtime) do
      {:ok, ndt} -> NaiveDateTime.to_string(ndt)
      _ -> "unknown"
    end
  end

  @spec sha256_hex(binary()) :: String.t()
  defp sha256_hex(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)

  @spec validate_expected_sha256(binary(), term()) :: :ok | {:error, atom()}
  defp validate_expected_sha256(_content, nil), do: :ok
  defp validate_expected_sha256(_content, ""), do: :ok

  defp validate_expected_sha256(content, expected) when is_binary(expected) do
    if sha256_hex(content) == String.downcase(expected) do
      :ok
    else
      {:error, :stale_file}
    end
  end

  defp validate_expected_sha256(_content, _expected), do: {:error, :invalid_expected_sha256}

  @spec replace_once(binary(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  defp replace_once(_content, "", _new_string), do: {:error, :empty_old_string}

  defp replace_once(content, old_string, new_string)
       when is_binary(old_string) and is_binary(new_string) do
    case :binary.matches(content, old_string) do
      [] -> {:error, :old_string_not_found}
      [_match] -> {:ok, String.replace(content, old_string, new_string, global: false)}
      _many -> {:error, :old_string_not_unique}
    end
  end

  defp replace_once(_content, _old_string, _new_string), do: {:error, :invalid_patch}

  @spec search_source_roots(map(), term()) :: {:ok, [String.t()]} | {:error, atom()}
  defp search_source_roots(project, nil), do: {:ok, project.source_roots}
  defp search_source_roots(project, ""), do: {:ok, project.source_roots}

  defp search_source_roots(project, source_root) when is_binary(source_root) do
    if source_root in project.source_roots do
      {:ok, [source_root]}
    else
      {:error, :invalid_source_root}
    end
  end

  defp search_source_roots(_project, _source_root), do: {:error, :invalid_source_root}

  @spec search_source_root(map(), String.t(), String.t()) :: [map()]
  defp search_source_root(_project, _source_root, ""), do: []

  defp search_source_root(project, source_root, query) do
    project
    |> Projects.list_source_tree()
    |> Enum.find_value([], fn
      %{source_root: ^source_root, nodes: nodes} -> nodes
      _ -> nil
    end)
    |> flatten_tree_files()
    |> Enum.flat_map(fn rel_path ->
      case Projects.read_source_file(project, source_root, rel_path) do
        {:ok, content} -> search_file_content(source_root, rel_path, content, query)
        {:error, _reason} -> []
      end
    end)
  end

  @spec flatten_tree_files([map()]) :: [String.t()]
  defp flatten_tree_files(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{type: :file, rel_path: rel_path} -> [rel_path]
      %{type: :dir, children: children} -> flatten_tree_files(children)
      %{"type" => :file, "rel_path" => rel_path} -> [rel_path]
      %{"type" => :dir, "children" => children} -> flatten_tree_files(children)
      _ -> []
    end)
  end

  @spec search_file_content(String.t(), String.t(), binary(), String.t()) :: [map()]
  defp search_file_content(source_root, rel_path, content, query) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if String.contains?(line, query) do
        [%{source_root: source_root, rel_path: rel_path, line: line_number, text: line}]
      else
        []
      end
    end)
  end

  @spec parse_diff_limit(term()) :: pos_integer()
  defp parse_diff_limit(value) when is_integer(value), do: value |> max(1) |> min(200_000)

  defp parse_diff_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> parse_diff_limit(parsed)
      _ -> 50_000
    end
  end

  defp parse_diff_limit(_value), do: 50_000

  @spec mcp_screenshot_entry(map()) :: map()
  defp mcp_screenshot_entry(shot) when is_map(shot) do
    target = Map.get(shot, :emulator_target)
    captured_at = Map.get(shot, :captured_at)

    %{
      filename: Map.get(shot, :filename),
      target_device: target,
      emulator_target: target,
      captured_at: captured_at,
      timestamp: captured_at,
      mime_type: Map.get(shot, :mime_type) || screenshot_mime_type(Map.get(shot, :filename)),
      url: Map.get(shot, :url),
      absolute_path: Map.get(shot, :absolute_path)
    }
  end

  @spec find_screenshot([map()], String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  defp find_screenshot(shots, emulator_target, filename) do
    case Enum.find(shots, &screenshot_match?(&1, emulator_target, filename)) do
      nil -> {:error, :screenshot_not_found}
      shot -> {:ok, shot}
    end
  end

  @spec screenshot_match?(map(), String.t(), String.t()) :: boolean()
  defp screenshot_match?(shot, emulator_target, filename) do
    Map.get(shot, :emulator_target) == emulator_target and Map.get(shot, :filename) == filename and
      is_binary(Map.get(shot, :absolute_path))
  end

  @spec screenshot_mime_type(String.t() | nil) :: String.t()
  defp screenshot_mime_type(filename) when is_binary(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/png"
    end
  end

  defp screenshot_mime_type(_filename), do: "application/octet-stream"

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

  @spec parse_render_tree_target(term()) :: {:ok, :watch | :companion | :phone} | {:error, atom()}
  defp parse_render_tree_target(nil), do: {:ok, :watch}
  defp parse_render_tree_target(""), do: {:ok, :watch}
  defp parse_render_tree_target("watch"), do: {:ok, :watch}
  defp parse_render_tree_target("companion"), do: {:ok, :companion}
  defp parse_render_tree_target("phone"), do: {:ok, :phone}
  defp parse_render_tree_target(:watch), do: {:ok, :watch}
  defp parse_render_tree_target(:companion), do: {:ok, :companion}
  defp parse_render_tree_target(:phone), do: {:ok, :phone}
  defp parse_render_tree_target(_target), do: {:error, :invalid_target}

  @spec parse_optional_debugger_targets(term()) ::
          {:ok, [:watch | :companion | :phone]} | {:error, atom()}
  defp parse_optional_debugger_targets(nil), do: {:ok, [:watch, :companion, :phone]}
  defp parse_optional_debugger_targets(""), do: {:ok, [:watch, :companion, :phone]}

  defp parse_optional_debugger_targets(target) do
    case parse_render_tree_target(target) do
      {:ok, target_atom} -> {:ok, [target_atom]}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec debugger_surface_runtime(map(), atom()) :: {:ok, map() | nil} | {:error, atom()}
  defp debugger_surface_runtime(state, target) when target in [:watch, :companion, :phone] do
    {:ok, Map.get(state, target)}
  end

  defp debugger_surface_runtime(_state, _target), do: {:error, :invalid_target}

  @spec surface_model_payload(map(), atom(), boolean()) :: map()
  defp surface_model_payload(state, target, include_view_output?)
       when target in [:watch, :companion, :phone] do
    runtime = Map.get(state, target) || %{}
    model = runtime_model_map(runtime)

    %{
      target: Atom.to_string(target),
      model: compact_debugger_model(model, include_view_output?),
      runtime_model:
        model
        |> map_get_any(["runtime_model", :runtime_model], %{})
        |> compact_debugger_model(include_view_output?),
      model_keys: model |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      runtime_model_keys:
        model
        |> map_get_any(["runtime_model", :runtime_model], %{})
        |> model_keys(),
      last_message: map_get_any(runtime, [:last_message, "last_message"], nil),
      view_tree_type:
        runtime
        |> map_get_any(["view_tree", :view_tree], %{})
        |> rendered_node_type()
    }
  end

  @spec compact_debugger_model(term(), boolean()) :: map()
  defp compact_debugger_model(model, include_view_output?) when is_map(model) do
    drop_keys =
      [
        "elm_executor_core_ir",
        :elm_executor_core_ir,
        "elm_executor_core_ir_b64",
        :elm_executor_core_ir_b64,
        "elm_executor_metadata",
        :elm_executor_metadata,
        "elm_introspect",
        :elm_introspect
      ] ++
        if include_view_output? do
          []
        else
          ["runtime_view_output", :runtime_view_output]
        end

    Map.drop(model, drop_keys)
  end

  defp compact_debugger_model(_model, _include_view_output?), do: %{}

  @spec model_keys(term()) :: [String.t()]
  defp model_keys(model) when is_map(model),
    do: model |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  defp model_keys(_model), do: []

  @spec maybe_render_tree_payload(map() | nil, map(), boolean()) :: map() | nil
  defp maybe_render_tree_payload(runtime, screen, true) when is_map(runtime) do
    case DebuggerSupport.rendered_tree(runtime) do
      %{} = tree ->
        nodes = flatten_rendered_nodes(tree, screen.width, screen.height)

        %{
          root_type: rendered_node_type(tree),
          node_count: length(nodes),
          nodes: nodes
        }

      _ ->
        nil
    end
  end

  defp maybe_render_tree_payload(_runtime, _screen, _include?), do: nil

  @spec preview_diagnostics_payload(
          String.t(),
          map(),
          map(),
          atom(),
          map(),
          map(),
          [map()],
          non_neg_integer() | nil
        ) :: map()
  defp preview_diagnostics_payload(
         slug,
         state,
         runtime,
         target,
         screen,
         runtime_fingerprints,
         events,
         cursor_seq
       ) do
    model = runtime_model_map(runtime)
    view_tree = map_get_any(runtime, ["view_tree", :view_tree], nil)
    rendered_tree = DebuggerSupport.rendered_tree(runtime)
    runtime_output = runtime_view_output_rows(model)
    render_source = preview_render_source(runtime_output, view_tree, rendered_tree)
    nodes = preview_nodes(rendered_tree, screen)
    root_type = rendered_node_type(rendered_tree)
    runtime_fingerprint = Map.get(runtime_fingerprints, target)
    surface_tree_sha256 = stable_term_sha256(view_tree)

    fingerprint_view_tree_sha256 =
      map_get_any(runtime_fingerprint || %{}, [:view_tree_sha256, "view_tree_sha256"], nil)

    %{
      slug: slug,
      target: Atom.to_string(target),
      seq: Map.get(state, :seq),
      revision: Map.get(state, :revision),
      watch_profile_id: Map.get(state, :watch_profile_id),
      screen: screen,
      status: preview_status(render_source, nodes),
      render_source: render_source,
      root_type: root_type,
      node_count: length(nodes),
      runtime_view_output_count: length(runtime_output),
      runtime_view_output_kinds: runtime_view_output_kinds(runtime_output),
      runtime_view_tree_type: rendered_node_type(view_tree),
      model_keys: model |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      runtime_model_keys:
        model
        |> map_get_any(["runtime_model", :runtime_model], %{})
        |> model_keys(),
      runtime_fingerprint: runtime_fingerprint,
      surface_tree_sha256: surface_tree_sha256,
      fingerprint_view_tree_sha256: fingerprint_view_tree_sha256,
      latest_render_events: DebuggerSupport.render_events_at_cursor(events, cursor_seq, 8),
      latest_lifecycle: DebuggerSupport.lifecycle_events_at_cursor(events, cursor_seq, 8),
      findings:
        preview_findings(
          render_source,
          rendered_tree,
          runtime_output,
          view_tree,
          surface_tree_sha256,
          fingerprint_view_tree_sha256
        )
    }
  end

  @spec runtime_view_output_rows(map()) :: [map()]
  defp runtime_view_output_rows(model) when is_map(model) do
    case map_get_any(model, ["runtime_view_output", :runtime_view_output], []) do
      rows when is_list(rows) -> Enum.filter(rows, &is_map/1)
      _ -> []
    end
  end

  defp runtime_view_output_rows(_model), do: []

  @spec runtime_view_output_kinds([map()]) :: [String.t()]
  defp runtime_view_output_kinds(rows) when is_list(rows) do
    rows
    |> Enum.map(fn row ->
      map_get_any(row, ["kind", :kind, "type", :type, "op", :op], nil)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.take(24)
  end

  @spec preview_render_source([map()], term(), term()) :: String.t()
  defp preview_render_source([_ | _], _view_tree, _rendered_tree), do: "runtime_view_output"

  defp preview_render_source([], %{} = view_tree, _rendered_tree) do
    if parser_expression_view_tree?(view_tree), do: "parser_view_tree", else: "runtime_view_tree"
  end

  defp preview_render_source([], _view_tree, %{}), do: "parser_view_tree"
  defp preview_render_source([], _view_tree, _rendered_tree), do: "none"

  @spec preview_status(String.t(), [map()]) :: String.t()
  defp preview_status("none", _nodes), do: "empty"
  defp preview_status("parser_view_tree", _nodes), do: "fallback"
  defp preview_status(_source, []), do: "empty"
  defp preview_status(_source, _nodes), do: "ok"

  @spec preview_nodes(term(), map()) :: [map()]
  defp preview_nodes(%{} = tree, screen) when is_map(screen) do
    flatten_rendered_nodes(
      tree,
      integer_or_default(map_get_any(screen, ["width", :width], nil), 0),
      integer_or_default(map_get_any(screen, ["height", :height], nil), 0)
    )
  end

  defp preview_nodes(_tree, _screen), do: []

  @spec preview_findings(String.t(), term(), [map()], term(), term(), term()) :: [String.t()]
  defp preview_findings(
         render_source,
         rendered_tree,
         runtime_output,
         view_tree,
         surface_tree_sha256,
         fingerprint_view_tree_sha256
       ) do
    []
    |> maybe_add_finding(runtime_output == [], "no_runtime_view_output")
    |> maybe_add_finding(rendered_tree == nil, "no_rendered_tree")
    |> maybe_add_finding(render_source == "parser_view_tree", "using_static_parser_view_tree")
    |> maybe_add_finding(
      fingerprint_view_tree_sha256_mismatch?(surface_tree_sha256, fingerprint_view_tree_sha256),
      "surface_tree_differs_from_runtime_fingerprint"
    )
    |> maybe_add_finding(
      parser_expression_view_tree?(view_tree),
      "runtime_view_tree_is_expression_outline"
    )
    |> Enum.reverse()
  end

  @spec maybe_add_finding([String.t()], boolean(), String.t()) :: [String.t()]
  defp maybe_add_finding(findings, true, finding), do: [finding | findings]
  defp maybe_add_finding(findings, false, _finding), do: findings

  @spec fingerprint_view_tree_sha256_mismatch?(term(), term()) :: boolean()
  defp fingerprint_view_tree_sha256_mismatch?(displayed, fingerprint)
       when is_binary(displayed) and is_binary(fingerprint) and displayed != "" and
              fingerprint != "",
       do: displayed != fingerprint

  defp fingerprint_view_tree_sha256_mismatch?(_displayed, _fingerprint), do: false

  @spec stable_term_sha256(term()) :: String.t() | nil
  defp stable_term_sha256(nil), do: nil

  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  @spec parser_expression_view_tree?(term()) :: boolean()
  defp parser_expression_view_tree?(%{"type" => type}) when is_binary(type),
    do: parser_expression_root_type?(type)

  defp parser_expression_view_tree?(%{type: type}) when is_binary(type),
    do: parser_expression_root_type?(type)

  defp parser_expression_view_tree?(_tree), do: false

  @spec parser_expression_root_type?(String.t()) :: boolean()
  defp parser_expression_root_type?(type)
       when type in [
              "toUiNode",
              "append",
              "List",
              "call",
              "expr",
              "var",
              "withDefault",
              "if",
              "case"
            ],
       do: true

  defp parser_expression_root_type?(_type), do: false

  @spec compact_debugger_event(map()) :: map()
  defp compact_debugger_event(event) when is_map(event) do
    payload = Map.get(event, :payload) || Map.get(event, "payload") || %{}

    %{
      seq: Map.get(event, :seq) || Map.get(event, "seq"),
      type: Map.get(event, :type) || Map.get(event, "type"),
      target: compact_event_target(payload),
      summary: compact_event_summary(event, payload),
      payload: compact_event_payload(payload)
    }
  end

  @spec compact_event_target(map()) :: String.t() | nil
  defp compact_event_target(payload) when is_map(payload) do
    value =
      map_get_any(
        payload,
        [
          :target,
          "target",
          :source_root,
          "source_root",
          :from,
          "from"
        ],
        nil
      )

    if is_nil(value), do: nil, else: to_string(value)
  end

  @spec compact_event_summary(map(), map()) :: String.t()
  defp compact_event_summary(event, payload) do
    type = Map.get(event, :type) || Map.get(event, "type") || "event"

    [
      map_get_any(payload, [:message, "message"], nil),
      map_get_any(payload, [:reason, "reason"], nil),
      map_get_any(payload, [:rel_path, "rel_path"], nil),
      map_get_any(payload, [:revision, "revision"], nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> case do
      [] -> to_string(type)
      parts -> Enum.join([to_string(type) | parts], " · ")
    end
  end

  @spec compact_event_payload(map()) :: map()
  defp compact_event_payload(payload) when is_map(payload) do
    payload
    |> Map.take([
      :target,
      "target",
      :message,
      "message",
      :message_source,
      "message_source",
      :rel_path,
      "rel_path",
      :source_root,
      "source_root",
      :reason,
      "reason",
      :revision,
      "revision",
      :status,
      "status",
      :error_count,
      "error_count",
      :warning_count,
      "warning_count",
      :from,
      "from",
      :to,
      "to"
    ])
    |> stringify_map_keys()
  end

  @spec stringify_map_keys(map()) :: map()
  defp stringify_map_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  @spec debugger_reload_source(map(), String.t(), String.t(), term()) ::
          {:ok, String.t()} | {:error, term()}
  defp debugger_reload_source(_project, _source_root, _rel_path, source) when is_binary(source),
    do: {:ok, source}

  defp debugger_reload_source(project, source_root, rel_path, _source) do
    case Projects.read_source_file(project, source_root, rel_path) do
      {:ok, source} -> {:ok, source}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec debugger_surface_screen(map(), map(), atom()) :: map()
  defp debugger_surface_screen(state, runtime, :watch) do
    launch_screen =
      state
      |> Map.get(:launch_context, %{})
      |> map_get_any(["screen", :screen], %{})

    model = runtime_model_map(runtime)

    %{
      width:
        integer_or_default(
          map_get_any(
            launch_screen,
            ["width", :width],
            map_get_any(model, ["screen_width"], 144)
          ),
          144
        ),
      height:
        integer_or_default(
          map_get_any(
            launch_screen,
            ["height", :height],
            map_get_any(model, ["screen_height"], 168)
          ),
          168
        )
    }
  end

  defp debugger_surface_screen(_state, runtime, _target) do
    box =
      runtime
      |> map_get_any(["view_tree", :view_tree], %{})
      |> map_get_any(["box", :box], %{})

    %{
      width: integer_or_default(map_get_any(box, ["w", :w], nil), 0),
      height: integer_or_default(map_get_any(box, ["h", :h], nil), 0)
    }
  end

  @spec runtime_model_map(map()) :: map()
  defp runtime_model_map(runtime) when is_map(runtime) do
    case map_get_any(runtime, ["model", :model], %{}) do
      model when is_map(model) -> model
      _ -> %{}
    end
  end

  defp runtime_model_map(_runtime), do: %{}

  @spec flatten_rendered_nodes(map(), integer(), integer()) :: [map()]
  defp flatten_rendered_nodes(tree, screen_w, screen_h) do
    do_flatten_rendered_nodes(tree, "0", tree, screen_w, screen_h)
  end

  @spec do_flatten_rendered_nodes(map(), String.t(), map(), integer(), integer()) :: [map()]
  defp do_flatten_rendered_nodes(node, path, root, screen_w, screen_h) when is_map(node) do
    current = %{
      path: path,
      type: rendered_node_type(node),
      label: rendered_node_label(node),
      bounds:
        DebuggerSupport.rendered_node_bounds(root, path, screen_w, screen_h) ||
          rendered_box_bounds(node),
      source: map_get_any(node, ["source", :source], nil)
    }

    children =
      node
      |> map_get_any(["children", :children], [])
      |> Enum.filter(&is_map/1)
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, index} ->
        do_flatten_rendered_nodes(child, "#{path}.#{index}", root, screen_w, screen_h)
      end)

    [current | children]
  end

  defp do_flatten_rendered_nodes(_node, _path, _root, _screen_w, _screen_h), do: []

  @spec rendered_node_type(term()) :: String.t()
  defp rendered_node_type(node) when is_map(node) do
    node
    |> map_get_any(["type", :type], "")
    |> to_string()
  end

  defp rendered_node_type(_node), do: ""

  @spec rendered_node_label(term()) :: String.t() | nil
  defp rendered_node_label(node) when is_map(node) do
    case map_get_any(node, ["label", :label, "text", :text], nil) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp rendered_node_label(_node), do: nil

  @spec rendered_box_bounds(term()) :: map() | nil
  defp rendered_box_bounds(node) when is_map(node) do
    case map_get_any(node, ["box", :box], nil) do
      %{} = box ->
        %{
          x: integer_or_default(map_get_any(box, ["x", :x], nil), 0),
          y: integer_or_default(map_get_any(box, ["y", :y], nil), 0),
          w: integer_or_default(map_get_any(box, ["w", :w], nil), 0),
          h: integer_or_default(map_get_any(box, ["h", :h], nil), 0)
        }

      _ ->
        nil
    end
  end

  defp rendered_box_bounds(_node), do: nil

  @spec map_get_any(map(), [term()], term()) :: term()
  defp map_get_any(map, keys, default) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, default, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp map_get_any(_map, _keys, default), do: default

  @spec integer_or_default(term(), integer()) :: integer()
  defp integer_or_default(value, _default) when is_integer(value), do: value

  defp integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> parsed
      _ -> default
    end
  end

  defp integer_or_default(_value, default), do: default

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

  @spec app_store_publisher_module() :: module()
  defp app_store_publisher_module do
    mcp_tools_config()
    |> Keyword.get(:app_store_publisher_module, AppStorePublisher)
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
