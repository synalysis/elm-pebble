defmodule Ide.Mcp.ToolCatalog do
  @moduledoc false

  alias Ide.EmulatorSupport
  alias Ide.Mcp.ConversionOpts
  alias Ide.Mcp.JsonSchema
  alias Ide.ProjectTemplates

  @type capability :: :read | :edit | :build | :publish

  @tool_version "1.0.0"
  @catalog_version "2026-05-28"

  @simulator_settings_schema %{
    type: "object",
    additionalProperties: JsonSchema.disallow_extra_properties(),
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
      accuracy: %{type: "number", minimum: 0, maximum: 100_000},
      weather: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        properties: %{
          condition: %{
            type: "string",
            enum: ["clear", "cloudy", "fog", "drizzle", "rain", "snow", "showers", "storm"]
          },
          temperatureC: %{type: "number"},
          humidityPercent: %{type: "number"},
          pressureHpa: %{type: "number"},
          windKph: %{type: "number"}
        }
      }
    }
  }

  @github_settings_schema %{
    type: "object",
    additionalProperties: JsonSchema.disallow_extra_properties(),
    properties: %{
      owner: %{type: "string"},
      repo: %{type: "string"},
      branch: %{type: "string"},
      visibility: %{type: "string", enum: ["public"]}
    }
  }

  @release_defaults_schema %{
    type: "object",
    additionalProperties: JsonSchema.disallow_extra_properties(),
    properties: %{
      version_label: %{type: "string"},
      tags: %{type: "string"},
      target_platforms: %{type: "array", items: %{type: "string"}},
      capabilities: %{type: "array", items: %{type: "string"}}
    }
  }

  @vector_conversion_opts ConversionOpts.input_schema_properties()
  @mcp_template_keys ProjectTemplates.template_keys()

  @read_tools [
    %{
      name: "templates.list",
      description: "List available project templates with labels and implied target types.",
      inputSchema: %{type: "object", additionalProperties: JsonSchema.disallow_extra_properties(), properties: %{}}
    },
    %{
      name: "projects.list",
      description: "List known IDE projects.",
      inputSchema: %{type: "object", additionalProperties: JsonSchema.disallow_extra_properties(), properties: %{}}
    },
    %{
      name: "projects.settings",
      description:
        "Read persisted project settings used by IDE automation, including release defaults, GitHub config, and debugger settings.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
      inputSchema: %{type: "object", additionalProperties: JsonSchema.disallow_extra_properties(), properties: %{}}
    },
    %{
      name: "audit.recent",
      description: "Read recent MCP action traces.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
        properties: %{
          limit: %{type: "integer", minimum: 1, maximum: 200}
        }
      }
    },
    %{
      name: "traces.policy",
      description: "Read effective trace retention policy defaults.",
      inputSchema: %{type: "object", additionalProperties: JsonSchema.disallow_extra_properties(), properties: %{}}
    },
    %{
      name: "traces.policy_validate",
      description: "Validate effective trace retention policy and return safety findings.",
      inputSchema: %{type: "object", additionalProperties: JsonSchema.disallow_extra_properties(), properties: %{}}
    },
    %{
      name: "debugger.state",
      description:
        "Read debugger runtime state snapshot for a project. Set replay_metadata_only=true for lightweight polling.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["slug"],
        properties: %{
          slug: %{type: "string"}
        }
      }
    },
    %{
      name: "debugger.watch_profiles",
      description: "List watch profiles available to debugger launch contexts.",
      inputSchema: %{type: "object", additionalProperties: JsonSchema.disallow_extra_properties(), properties: %{}}
    },
    %{
      name: "resources.vectors.list",
      description: "List vector graphic manifest entries for a project.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["slug"],
        properties: %{slug: %{type: "string"}}
      }
    },
    %{
      name: "resources.vectors.convert",
      description: "Convert an SVG string to PDCI bytes with a structured conversion report.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["svg"],
        properties: Map.merge(%{svg: %{type: "string"}}, @vector_conversion_opts)
      }
    },
    %{
      name: "resources.vectors.convert_sequence",
      description: "Convert a list of SVG frame strings to PDCS bytes.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["frames"],
        properties:
          Map.merge(
            %{frames: %{type: "array", items: %{type: "string"}, minItems: 1}},
            @vector_conversion_opts
          )
      }
    },
    %{
      name: "resources.vectors.preview",
      description: "Render a PDC asset or project constructor to SVG preview text.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        properties: %{
          slug: %{type: "string"},
          ctor: %{type: "string"},
          bytes_base64: %{type: "string"},
          frame: %{type: "integer", minimum: 0, default: 0}
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["name", "slug"],
        properties: %{
          name: %{type: "string"},
          slug: %{type: "string"},
          target_type: %{type: "string", enum: ["app", "watchface", "companion"]},
          template: %{type: "string", enum: @mcp_template_keys}
        }
      }
    },
    %{
      name: "projects.delete",
      description: "Delete an IDE project and remove its local workspace.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
            additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["slug", "values"],
        properties: %{
          slug: %{type: "string"},
          values: %{type: "object", additionalProperties: JsonSchema.allow_extra_properties()}
        }
      }
    },
    %{
      name: "debugger.set_auto_fire",
      description: "Persist and apply debugger natural subscription auto-fire settings.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
    },
    %{
      name: "resources.vectors.import",
      description: "Convert an SVG string and import it as a project vector resource.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["slug", "svg"],
        properties:
          Map.merge(
            %{
              slug: %{type: "string"},
              svg: %{type: "string"},
              name: %{type: "string", description: "Optional original filename hint."}
            },
            @vector_conversion_opts
          )
      }
    },
    %{
      name: "resources.vectors.import_sequence",
      description: "Convert SVG frames and import a PDCS sequence resource.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["slug", "frames"],
        properties:
          Map.merge(
            %{
              slug: %{type: "string"},
              frames: %{type: "array", items: %{type: "string"}, minItems: 1},
              name: %{type: "string", description: "Optional sequence filename hint."}
            },
            @vector_conversion_opts
          )
      }
    },
    %{
      name: "resources.vectors.delete",
      description: "Delete a vector resource constructor and regenerate Resources module.",
      inputSchema: %{
        type: "object",
        additionalProperties: JsonSchema.disallow_extra_properties(),
        required: ["slug", "ctor"],
        properties: %{
          slug: %{type: "string"},
          ctor: %{type: "string"}
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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
        additionalProperties: JsonSchema.disallow_extra_properties(),
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

  @spec add_if(list(), boolean(), list()) :: list()
  defp add_if(list, condition, entries) when is_boolean(condition) do
    if condition, do: list ++ entries, else: list
  end

  @spec publish_tool_name(map()) :: map()
  defp publish_tool_name(%{name: name} = tool) when is_binary(name) do
    %{tool | name: Map.fetch!(@public_tool_names_by_internal, name)}
  end

  @spec internal_tool_name(String.t()) :: String.t()
  def internal_tool_name(name) when is_binary(name) do
    cond do
      MapSet.member?(@internal_tool_names, name) -> name
      internal = Map.get(@internal_tool_names_by_public, name) -> internal
      true -> name
    end
  end

  def authorized?("templates.list", capabilities), do: :read in capabilities
  def authorized?("projects.list", capabilities), do: :read in capabilities
  def authorized?("projects.settings", capabilities), do: :read in capabilities
  def authorized?("projects.tree", capabilities), do: :read in capabilities
  def authorized?("files.read", capabilities), do: :read in capabilities
  def authorized?("files.stat", capabilities), do: :read in capabilities
  def authorized?("files.read_range", capabilities), do: :read in capabilities
  def authorized?("files.search", capabilities), do: :read in capabilities
  def authorized?("projects.diff", capabilities), do: :read in capabilities
  def authorized?("screenshots.list", capabilities), do: :read in capabilities
  def authorized?("screenshots.read", capabilities), do: :read in capabilities
  def authorized?("packages.search", capabilities), do: :read in capabilities
  def authorized?("packages.details", capabilities), do: :read in capabilities
  def authorized?("packages.versions", capabilities), do: :read in capabilities
  def authorized?("packages.readme", capabilities), do: :read in capabilities
  def authorized?("packages.module_docs", capabilities), do: :read in capabilities
  def authorized?("projects.graph", capabilities), do: :read in capabilities
  def authorized?("audit.recent", capabilities), do: :read in capabilities
  def authorized?("compiler.check_cached", capabilities), do: :read in capabilities
  def authorized?("compiler.check_recent", capabilities), do: :read in capabilities
  def authorized?("compiler.compile_cached", capabilities), do: :read in capabilities
  def authorized?("compiler.compile_recent", capabilities), do: :read in capabilities
  def authorized?("compiler.manifest_cached", capabilities), do: :read in capabilities
  def authorized?("compiler.manifest_recent", capabilities), do: :read in capabilities
  def authorized?("sessions.recent_activity", capabilities), do: :read in capabilities
  def authorized?("sessions.summary", capabilities), do: :read in capabilities
  def authorized?("sessions.trace_health", capabilities), do: :read in capabilities
  def authorized?("traces.bundle", capabilities), do: :read in capabilities
  def authorized?("traces.summary", capabilities), do: :read in capabilities
  def authorized?("traces.export", capabilities), do: :read in capabilities
  def authorized?("traces.exports_list", capabilities), do: :read in capabilities
  def authorized?("traces.policy", capabilities), do: :read in capabilities
  def authorized?("traces.policy_validate", capabilities), do: :read in capabilities
  def authorized?("debugger.state", capabilities), do: :read in capabilities
  def authorized?("debugger.export_trace", capabilities), do: :read in capabilities
  def authorized?("debugger.cursor_inspect", capabilities), do: :read in capabilities
  def authorized?("debugger.render_tree", capabilities), do: :read in capabilities
  def authorized?("debugger.preview_diagnostics", capabilities), do: :read in capabilities
  def authorized?("debugger.models", capabilities), do: :read in capabilities
  def authorized?("debugger.timeline", capabilities), do: :read in capabilities
  def authorized?("debugger.surface_state", capabilities), do: :read in capabilities
  def authorized?("debugger.simulator_settings", capabilities), do: :read in capabilities
  def authorized?("debugger.configuration", capabilities), do: :read in capabilities
  def authorized?("debugger.auto_fire", capabilities), do: :read in capabilities
  def authorized?("debugger.disabled_subscriptions", capabilities), do: :read in capabilities
  def authorized?("debugger.watch_profiles", capabilities), do: :read in capabilities
  def authorized?("resources.vectors.list", capabilities), do: :read in capabilities
  def authorized?("resources.vectors.convert", capabilities), do: :read in capabilities
  def authorized?("resources.vectors.convert_sequence", capabilities), do: :read in capabilities
  def authorized?("resources.vectors.preview", capabilities), do: :read in capabilities
  def authorized?("projects.create", capabilities), do: :edit in capabilities
  def authorized?("projects.delete", capabilities), do: :edit in capabilities
  def authorized?("projects.update_settings", capabilities), do: :edit in capabilities
  def authorized?("files.write", capabilities), do: :edit in capabilities
  def authorized?("files.patch", capabilities), do: :edit in capabilities
  def authorized?("packages.add_to_elm_json", capabilities), do: :edit in capabilities
  def authorized?("packages.remove_from_elm_json", capabilities), do: :edit in capabilities
  def authorized?("traces.export_write", capabilities), do: :edit in capabilities
  def authorized?("traces.exports_prune", capabilities), do: :edit in capabilities
  def authorized?("traces.maintenance", capabilities), do: :edit in capabilities
  def authorized?("debugger.start", capabilities), do: :edit in capabilities
  def authorized?("debugger.reset", capabilities), do: :edit in capabilities
  def authorized?("debugger.set_watch_profile", capabilities), do: :edit in capabilities
  def authorized?("debugger.set_simulator_settings", capabilities), do: :edit in capabilities
  def authorized?("debugger.save_configuration", capabilities), do: :edit in capabilities
  def authorized?("debugger.set_auto_fire", capabilities), do: :edit in capabilities
  def authorized?("debugger.set_subscription_enabled", capabilities), do: :edit in capabilities
  def authorized?("debugger.reload", capabilities), do: :edit in capabilities
  def authorized?("debugger.step", capabilities), do: :edit in capabilities
  def authorized?("debugger.tick", capabilities), do: :edit in capabilities
  def authorized?("debugger.auto_tick_start", capabilities), do: :edit in capabilities
  def authorized?("debugger.auto_tick_stop", capabilities), do: :edit in capabilities
  def authorized?("debugger.replay_recent", capabilities), do: :edit in capabilities
  def authorized?("debugger.continue_from_snapshot", capabilities), do: :edit in capabilities
  def authorized?("debugger.import_trace", capabilities), do: :edit in capabilities
  def authorized?("resources.vectors.import", capabilities), do: :edit in capabilities
  def authorized?("resources.vectors.import_sequence", capabilities), do: :edit in capabilities
  def authorized?("resources.vectors.delete", capabilities), do: :edit in capabilities
  def authorized?("pebble.package", capabilities), do: :build in capabilities
  def authorized?("pebble.install", capabilities), do: :build in capabilities
  def authorized?("screenshots.capture", capabilities), do: :build in capabilities
  def authorized?("compiler.check", capabilities), do: :build in capabilities
  def authorized?("compiler.check_source_root", capabilities), do: :build in capabilities
  def authorized?("compiler.compile", capabilities), do: :build in capabilities
  def authorized?("compiler.manifest", capabilities), do: :build in capabilities
  def authorized?("publish.prepare", capabilities), do: :build in capabilities
  def authorized?("publish.validate", capabilities), do: :build in capabilities
  def authorized?("publish.submit", capabilities), do: :publish in capabilities
  def authorized?(_, _), do: false

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

end
