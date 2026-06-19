defmodule Ide.Mcp.DebuggerTemplateCorpus do
  @moduledoc """
  MCP-driven debugger bootstrap and snapshot capture for project templates.

  Used by `Ide.Mcp.DebuggerTemplateCorpusTest` to create a project per template,
  start the debugger once, and compare watch models, render trees, and canonical
  preview SVG ops against checked-in fixtures.
  """

  alias Ide.Debugger
  alias Ide.Debugger.CompanionSubscriptionTrigger
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.Tools
  alias Ide.ProjectTemplates
  alias Ide.ProjectTemplates.SourceValidation
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerPreview

  @capabilities [:read, :edit]

  @phone_first_templates ~w(
    watchface-yes
    watchface-tangram-time
    watchface-weather-animated
    watchface-tutorial-complete
    companion-demo-phone-status
    companion-demo-weather-env
    companion-demo-calendar
    companion-demo-geolocation
    companion-demo-storage
    companion-demo-settings
    companion-demo-websocket
    companion-demo-timeline
  )

  @aplite_profile_templates ~w(watch-demo-compass)

  @fixtures_root Path.expand(
                   "../../../test/fixtures/debugger_template_corpus",
                   __DIR__
                 )

  @doc "All project template keys exercised by the corpus."
  @spec template_keys() :: [String.t()]
  def template_keys, do: ProjectTemplates.template_keys()

  @doc "Templates included in the subscription-step runtime execution corpus gate."
  @spec subscription_step_template_keys() :: [String.t()]
  def subscription_step_template_keys, do: template_keys()

  @doc "Directory holding per-template expected snapshot JSON."
  @spec fixtures_root() :: String.t()
  def fixtures_root, do: @fixtures_root

  @spec fixture_path(String.t()) :: String.t()
  def fixture_path(template_key) when is_binary(template_key) do
    Path.join(fixtures_root(), template_key <> ".json")
  end

  @doc """
  Creates the project, starts the debugger, reloads template sources, and returns a snapshot map.
  """
  @spec run_template(String.t(), keyword()) ::
          {:ok, %{slug: String.t(), project: Projects.Project.t(), snapshot: map()}}
          | {:error, term()}
  def run_template(template_key, opts \\ []) when is_binary(template_key) do
    unless template_key in template_keys() do
      raise ArgumentError, "unknown template #{inspect(template_key)}"
    end

    seed_corpus_random!()

    slug = Keyword.get(opts, :slug) || unique_slug(template_key)
    cleanup? = Keyword.get(opts, :cleanup, true)

    with :ok <- SourceValidation.validate_template(template_key),
         {:ok, project} <- create_project(slug, template_key),
         :ok <- bootstrap(slug, project, template_key),
         {:ok, snapshot} <- capture(slug, project, template_key) do
      if cleanup?, do: _ = Projects.delete_project(project)
      {:ok, %{slug: slug, project: project, snapshot: snapshot}}
    end
  end

  @doc """
  Bootstraps a template project in the debugger without capturing a snapshot.

  Used to exercise subscription steps after bootstrap without mutating corpus fixtures.
  """
  @spec bootstrap_template(String.t(), keyword()) ::
          {:ok, %{slug: String.t(), project: Projects.Project.t()}} | {:error, term()}
  def bootstrap_template(template_key, opts \\ []) when is_binary(template_key) do
    unless template_key in template_keys() do
      raise ArgumentError, "unknown template #{inspect(template_key)}"
    end

    slug = Keyword.get(opts, :slug) || unique_slug(template_key)
    cleanup? = Keyword.get(opts, :cleanup, true)

    with :ok <- SourceValidation.validate_template(template_key),
         {:ok, project} <- create_project(slug, template_key),
         :ok <- bootstrap(slug, project, template_key) do
      if cleanup?, do: _ = Projects.delete_project(project)
      {:ok, %{slug: slug, project: project}}
    end
  end

  @doc """
  Injects the first contract-discovered subscription trigger per surface and
  asserts runtime execution handled the update (not `update_evaluation_failed`).
  """
  @spec assert_subscription_steps_runtime!(String.t(), String.t()) :: :ok
  def assert_subscription_steps_runtime!(slug, template_key)
      when is_binary(slug) and is_binary(template_key) do
    if template_key in @phone_first_templates do
      :ok = assert_companion_subscription_step_runtime!(slug, template_key)
    end

    :ok = assert_watch_subscription_step_runtime!(slug, template_key)
  end

  @doc "Loads the checked-in fixture for a template, if present."
  @spec load_fixture(String.t()) :: {:ok, map()} | {:error, :missing}
  def load_fixture(template_key) when is_binary(template_key) do
    path = fixture_path(template_key)

    if File.exists?(path) do
      {:ok, path |> File.read!() |> Jason.decode!()}
    else
      {:error, :missing}
    end
  end

  @doc "Writes a normalized snapshot fixture for a template."
  @spec write_fixture!(String.t(), map()) :: :ok
  def write_fixture!(template_key, snapshot) when is_binary(template_key) and is_map(snapshot) do
    path = fixture_path(template_key)
    File.mkdir_p!(Path.dirname(path))

    path
    |> File.write!(Jason.encode!(snapshot, pretty: true) <> "\n")

    :ok
  end

  @doc "Compares a captured snapshot to an expected fixture map."
  @spec compare_snapshots(map(), map()) :: :ok | {:error, String.t()}
  def compare_snapshots(actual, expected) when is_map(actual) and is_map(expected) do
    actual_norm = normalize_snapshot(actual)
    expected_norm = normalize_snapshot(expected)

    if actual_norm == expected_norm do
      :ok
    else
      diff = snapshot_diff(actual_norm, expected_norm)
      {:error, "snapshot mismatch\n#{diff}"}
    end
  end

  @spec create_project(String.t(), String.t()) ::
          {:ok, Projects.Project.t()} | {:error, term()}
  defp create_project(slug, template_key) do
    with {:ok, created} <-
           Tools.call(
             "projects.create",
             %{
               "name" => "Corpus #{template_key}",
               "slug" => slug,
               "target_type" => ProjectTemplates.target_type_for_template(template_key),
               "template" => template_key
             },
             @capabilities
           ),
         {:ok, project} <- ToolSupport.fetch_project(created.slug) do
      {:ok, project}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec bootstrap(String.t(), Projects.Project.t(), String.t()) :: :ok | {:error, term()}
  defp bootstrap(slug, project, template_key) do
    seed_corpus_random!()

    with {:ok, _} <- Tools.call("debugger.start", %{"slug" => slug}, @capabilities),
         {:ok, _} <-
           Tools.call(
             "debugger.set_watch_profile",
             %{"slug" => slug, "watch_profile_id" => watch_profile_for(template_key)},
             @capabilities
           ),
         {:ok, _} <- apply_simulator_settings(slug, template_key),
         :ok <- reload_surfaces(slug, project, template_key),
         :ok <- after_bootstrap(slug, template_key),
         :ok <- await_background_idle!(slug) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec apply_simulator_settings(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defp apply_simulator_settings(slug, template_key) do
    settings =
      %{
        "use_simulated_time" => true,
        "simulated_date" => "2026-05-27",
        "simulated_time" => "08:53:00",
        "timezone_offset_min" => 0
      }
      |> Map.merge(template_simulator_extras(template_key))

    Tools.call(
      "debugger.set_simulator_settings",
      %{"slug" => slug, "settings" => settings},
      @capabilities
    )
  end

  @spec template_simulator_extras(String.t()) :: map()
  defp template_simulator_extras("watchface-weather-animated"),
    do: %{"weather" => %{"temperatureC" => 18, "condition" => "fog"}}

  defp template_simulator_extras("companion-demo-geolocation"),
    do: %{"latitude" => 48.137154, "longitude" => 11.576124, "accuracy" => 25.0}

  defp template_simulator_extras(_), do: %{}

  @spec after_bootstrap(String.t(), String.t()) :: :ok | {:error, term()}
  defp after_bootstrap(slug, "watchface-weather-animated") do
    case Debugger.inject_trigger(slug, %{
           target: "watch",
           trigger: "timer",
           message: "EnableWeatherTransitions"
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp after_bootstrap(_slug, _template_key), do: :ok

  @spec reload_surfaces(String.t(), Projects.Project.t(), String.t()) :: :ok | {:error, term()}
  defp reload_surfaces(slug, project, template_key) do
    with :ok <- maybe_reload_phone(slug, project, template_key),
         {:ok, _} <- reload_watch(slug, project) do
      :ok
    end
  end

  @spec maybe_reload_phone(String.t(), Projects.Project.t(), String.t()) :: :ok | {:error, term()}
  defp maybe_reload_phone(slug, project, template_key) do
    if template_key in @phone_first_templates do
      with {:ok, source} <- Projects.read_source_file(project, "phone", "src/CompanionApp.elm"),
           {:ok, _} <-
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => slug,
                 "rel_path" => "src/CompanionApp.elm",
                 "source" => source,
                 "source_root" => "phone",
                 "reason" => "template_corpus_phone"
               },
               @capabilities
             ) do
        :ok
      end
    else
      :ok
    end
  end

  @spec reload_watch(String.t(), Projects.Project.t()) :: {:ok, map()} | {:error, term()}
  defp reload_watch(slug, project) do
    with {:ok, source} <- Projects.read_source_file(project, "watch", "src/Main.elm") do
      Tools.call(
        "debugger.reload",
        %{
          "slug" => slug,
          "rel_path" => "src/Main.elm",
          "source" => source,
          "source_root" => "watch",
          "reason" => "template_corpus_watch"
        },
        @capabilities
      )
    end
  end

  @spec capture(String.t(), Projects.Project.t(), String.t()) ::
          {:ok, map()} | {:error, String.t() | term()}
  defp capture(slug, project, template_key) do
    with {:ok, models} <-
           Tools.call(
             "debugger.models",
             %{"slug" => slug, "target" => "watch", "include_view_output" => true},
             @capabilities
           ),
         {:ok, render_tree} <-
           Tools.call(
             "debugger.render_tree",
             %{"slug" => slug, "target" => "watch", "include_tree" => true},
             @capabilities
           ),
         {:ok, diagnostics} <-
           Tools.call(
             "debugger.preview_diagnostics",
             %{"slug" => slug, "target" => "watch"},
             @capabilities
           ),
         :ok <- await_background_idle!(slug),
         {:ok, state} <- Debugger.snapshot(slug, event_limit: 200) do
      :ok = assert_surfaces_versioned_runtime_artifacts!(state, template_key)
      :ok = assert_watch_executor_ready!(state, template_key)
      :ok = assert_companion_runtime_model!(state, template_key)
      :ok = assert_companion_executor_ready!(state, template_key)

      models_map = Map.get(models, :models) || Map.get(models, "models") || %{}

      watch_entry =
        Map.get(models_map, "watch") || Map.get(models_map, :watch) || %{}

      runtime = Map.get(state, :watch) || %{}
      preview_ops = preview_ops_for_runtime(runtime, project)

      snapshot =
        %{
          "template" => template_key,
          "watch_model" => Map.get(watch_entry, :model) || Map.get(watch_entry, "model") || %{},
          "runtime_model" =>
            Map.get(watch_entry, :runtime_model) || Map.get(watch_entry, "runtime_model") || %{},
          "view_tree_type" =>
            Map.get(watch_entry, :view_tree_type) || Map.get(watch_entry, "view_tree_type"),
          "render_tree" => render_tree_payload(render_tree),
          "preview_diagnostics" => preview_diagnostics_payload(diagnostics),
          "preview_ops" => preview_ops,
          "preview_ops_sha256" => StepExecution.stable_term_sha256(preview_ops),
          "timeline_init_messages" => timeline_init_messages(state)
        }

      {:ok, normalize_snapshot(snapshot)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec preview_ops_for_runtime(map(), Projects.Project.t()) :: [map()]
  defp preview_ops_for_runtime(runtime, project) when is_map(runtime) do
    tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    tree
    |> DebuggerPreview.svg_ops(runtime)
    |> DebuggerPreview.hydrate_animation_svg_ops(project)
    |> DebuggerPreview.hydrate_vector_svg_ops(project)
    |> Enum.map(&canonical_svg_op/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec canonical_svg_op(map()) :: map() | nil
  defp canonical_svg_op(op) when is_map(op) do
    kind = op |> Map.get(:kind) |> normalize_kind()

    base =
      op
      |> Map.drop([:points, :frames, :path, "points", "frames", "path"])
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("kind", kind)

    case kind do
      "vector_sequence_anim" ->
        Map.take(base, ["kind", "vector_id", "x", "y", "frame_count"])

      "unresolved" ->
        Map.take(base, ["kind", "label", "reason"])

      _ ->
        base
    end
  end

  defp canonical_svg_op(_), do: nil

  @spec normalize_kind(term()) :: String.t()
  defp normalize_kind(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp normalize_kind(kind) when is_binary(kind), do: kind
  defp normalize_kind(_), do: "unknown"

  @spec render_tree_payload(map()) :: map()
  defp render_tree_payload(render_tree) when is_map(render_tree) do
    tree = Map.get(render_tree, :tree) || Map.get(render_tree, "tree")
    nodes = Map.get(render_tree, :nodes) || Map.get(render_tree, "nodes") || []

    %{
      "root_type" => Map.get(render_tree, :root_type) || Map.get(render_tree, "root_type"),
      "node_count" => Map.get(render_tree, :node_count) || Map.get(render_tree, "node_count"),
      "node_types" =>
        nodes
        |> Enum.map(fn node ->
          node |> Map.get("type") || Map.get(node, :type) |> to_string()
        end)
        |> Enum.sort(),
      "tree" => normalize_render_tree(tree)
    }
  end

  @spec preview_diagnostics_payload(map()) :: map()
  defp preview_diagnostics_payload(diag) when is_map(diag) do
    %{
      "status" => Map.get(diag, :status) || Map.get(diag, "status"),
      "render_source" => Map.get(diag, :render_source) || Map.get(diag, "render_source"),
      "root_type" => Map.get(diag, :root_type) || Map.get(diag, "root_type"),
      "runtime_view_output_kinds" =>
        Map.get(diag, :runtime_view_output_kinds) || Map.get(diag, "runtime_view_output_kinds") ||
          []
    }
  end

  @spec timeline_init_messages(map()) :: [String.t()]
  defp timeline_init_messages(state) when is_map(state) do
    state
    |> Map.get(:debugger_timeline, [])
    |> Enum.take(8)
    |> Enum.map(fn row ->
      type = Map.get(row, :type) || Map.get(row, "type")
      message = Map.get(row, :message) || Map.get(row, "message")
      "#{type}:#{normalize_timeline_message(message)}"
    end)
  end

  @spec normalize_timeline_message(String.t() | nil) :: String.t()
  defp normalize_timeline_message(message) when is_binary(message) do
    Regex.replace(~r/^RandomGenerated \d+$/, message, "RandomGenerated <seed>")
  end

  defp normalize_timeline_message(message), do: to_string(message || "")

  @spec normalize_snapshot(map()) :: map()
  def normalize_snapshot(snapshot) when is_map(snapshot) do
    snapshot
    |> normalize_model_field("watch_model")
    |> normalize_model_field("runtime_model")
    |> normalize_render_tree_field()
    |> Map.update("preview_ops", [], &normalize_preview_ops/1)
    |> Map.update("timeline_init_messages", [], &normalize_timeline_messages/1)
  end

  @spec normalize_timeline_messages([String.t()]) :: [String.t()]
  defp normalize_timeline_messages(messages) when is_list(messages) do
    Enum.map(messages, &normalize_timeline_entry/1)
  end

  defp normalize_timeline_entry(entry) when is_binary(entry) do
    case String.split(entry, ":", parts: 2) do
      [type, message] -> "#{type}:#{normalize_timeline_message(message)}"
      _ -> entry
    end
  end

  defp normalize_timeline_entry(entry), do: entry

  @spec normalize_model_field(map(), String.t()) :: map()
  defp normalize_model_field(snapshot, key) do
    Map.update(snapshot, key, %{}, &normalize_model/1)
  end

  @spec normalize_render_tree_field(map()) :: map()
  defp normalize_render_tree_field(snapshot) do
    Map.update(snapshot, "render_tree", %{}, fn tree ->
      tree
      |> Map.update("tree", nil, &normalize_render_tree/1)
      |> Map.update("node_types", [], fn types ->
        types |> List.wrap() |> Enum.sort()
      end)
    end)
  end

  @spec normalize_model(map()) :: map()
  defp normalize_model(model) when is_map(model) do
    model
    |> drop_volatile_model_keys()
    |> normalize_time_fields()
    |> Map.new(fn {k, v} -> {to_string(k), normalize_value(v)} end)
    |> Map.new()
  end

  defp normalize_model(other), do: other

  @spec drop_volatile_model_keys(map()) :: map()
  defp drop_volatile_model_keys(model) do
    model
    |> Map.drop([
      "elm_introspect",
      "debugger_contract",
      "debugger_contract_b64",
      "runtime_model_sha256",
      "runtime_view_output_model_sha256",
      "runtime_view_tree_sha256",
      "last_path",
      "last_source",
      "last_runtime_step_message",
      "last_runtime_step_op",
      "runtime_last_message",
      "revision",
      "launch_context",
      "simulator_settings",
      "runtime_execution",
      "runtime_execution_mode",
      "runtime_model_source",
      "runtime_message_cursor",
      "runtime_message_source",
      "runtime_view_tree_source",
      "runtime_known_messages",
      "runtime_update_branches",
      "runtime_view_output",
      "source_root",
      "status",
      "supports_color",
      "screen_height",
      "screen_width",
      "_debugger_steps"
    ])
    |> Enum.reject(fn {key, _} ->
      key = to_string(key)
      String.starts_with?(key, "debugger_device_")
    end)
    |> Map.new()
  end

  @spec normalize_time_fields(map()) :: map()
  defp normalize_time_fields(model) do
    model
    |> Map.update("timeString", nil, &normalize_time_string/1)
    |> Map.update("runtime_view_output", [], fn rows ->
      Enum.map(List.wrap(rows), &normalize_view_output_row/1)
    end)
  end

  @spec normalize_time_string(term()) :: term()
  defp normalize_time_string(value) when is_binary(value) do
    if Regex.match?(~r/^\d{2}:\d{2}$/, value), do: "<TIME>", else: value
  end

  defp normalize_time_string(value), do: value

  @spec normalize_view_output_row(map()) :: map()
  defp normalize_view_output_row(row) when is_map(row) do
    row
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("text", nil, &normalize_time_string/1)
    |> Map.drop(["source"])
  end

  defp normalize_view_output_row(row), do: row

  @spec normalize_render_tree(term()) :: term()
  defp normalize_render_tree(tree) when is_map(tree) do
    tree
    |> Map.drop(["source"])
    |> Map.new(fn {k, v} -> {to_string(k), normalize_render_tree(v)} end)
    |> Map.update("text", nil, &normalize_time_string/1)
  end

  defp normalize_render_tree(list) when is_list(list) do
    list
    |> Enum.map(&normalize_render_tree/1)
    |> Enum.sort_by(&render_tree_sort_key/1)
  end

  defp normalize_render_tree(other), do: normalize_value(other)

  @spec render_tree_sort_key(term()) :: term()
  defp render_tree_sort_key(node) when is_map(node) do
    {Map.get(node, "type"), Map.get(node, "kind"), Map.get(node, "text"), Map.get(node, "label")}
  end

  defp render_tree_sort_key(node), do: node

  @spec normalize_preview_ops(list()) :: list()
  defp normalize_preview_ops(ops) when is_list(ops) do
    Enum.map(ops, &normalize_value/1)
  end

  @snapshot_hash_keys ~w(
    runtime_view_output_model_sha256
    runtime_view_tree_sha256
    runtime_model_sha256
  )

  @spec normalize_value(term()) :: term()
  defp normalize_value(map) when is_map(map) do
    map
    |> Map.drop(@snapshot_hash_keys)
    |> Map.new(fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value({a, b}), do: [normalize_value(a), normalize_value(b)]

  defp normalize_value(atom) when is_atom(atom) do
    case atom do
      true -> true
      false -> false
      nil -> nil
      other -> Atom.to_string(other)
    end
  end

  defp normalize_value(n) when is_float(n), do: Float.round(n, 2)

  defp normalize_value(other), do: other

  @spec watch_profile_for(String.t()) :: String.t()
  defp watch_profile_for(template_key) when template_key in @aplite_profile_templates,
    do: "aplite"

  defp watch_profile_for(template_key) do
    template_key
    |> ProjectTemplates.target_platforms_for_template()
    |> List.first("aplite")
  end

  @spec unique_slug(String.t()) :: String.t()
  defp unique_slug(template_key) do
    "corpus-#{template_key}-#{System.unique_integer([:positive])}"
  end

  @doc false
  @spec assert_surfaces_versioned_runtime_artifacts!(map(), String.t()) :: :ok
  def assert_surfaces_versioned_runtime_artifacts!(state, template_key)
      when is_map(state) and is_binary(template_key) do
    unless SurfaceCompileArtifacts.surface_has_versioned_runtime_artifacts?(state, :watch) do
      raise "template #{template_key}: watch surface missing versioned elmx artifacts after bootstrap"
    end

    if template_key in @phone_first_templates do
      unless SurfaceCompileArtifacts.surface_has_versioned_runtime_artifacts?(state, :companion) do
        raise "template #{template_key}: companion surface missing versioned elmx artifacts after bootstrap"
      end
    end

    :ok
  end

  @doc false
  @spec assert_companion_runtime_model!(map(), String.t()) :: :ok
  def assert_companion_runtime_model!(state, template_key)
      when is_map(state) and is_binary(template_key) do
    if template_key in @phone_first_templates do
      runtime_model = get_in(state, [:companion, :model, "runtime_model"]) || %{}

      if map_size(runtime_model) == 0 do
        raise "template #{template_key}: companion runtime_model empty after bootstrap"
      end

      case template_key do
        "companion-demo-phone-status" ->
          unless is_integer(runtime_model["batteryPercent"]) do
            raise "template #{template_key}: expected batteryPercent on companion runtime_model, got #{inspect(runtime_model)}"
          end

          unless is_binary(runtime_model["locale"]) do
            raise "template #{template_key}: expected locale string on companion runtime_model, got #{inspect(runtime_model)}"
          end

        _ ->
          :ok
      end
    end

    :ok
  end

  @doc false
  @spec assert_watch_executor_ready!(map(), String.t()) :: :ok
  def assert_watch_executor_ready!(state, template_key)
      when is_map(state) and is_binary(template_key) do
    operation_source =
      get_in(state, [:watch, :model, "runtime_execution", "operation_source"]) ||
        get_in(state, [:watch, :model, :runtime_execution, :operation_source])

    if operation_source == "update_evaluation_failed" do
      raise "template #{template_key}: watch runtime update failed during bootstrap"
    end

    :ok
  end

  @doc false
  @spec assert_companion_executor_ready!(map(), String.t()) :: :ok
  def assert_companion_executor_ready!(state, template_key)
      when is_map(state) and is_binary(template_key) do
    if template_key in @phone_first_templates do
      operation_source =
        get_in(state, [:companion, :model, "runtime_execution", "operation_source"]) ||
          get_in(state, [:companion, :model, :runtime_execution, :operation_source])

      if operation_source == "update_evaluation_failed" do
        raise "template #{template_key}: companion runtime update failed during bootstrap"
      end
    end

    :ok
  end

  @runtime_step_success_sources ~w(
    runtime_update_eval
    runtime_update_noop
    core_ir_update_eval
    core_ir_update_noop
    step_message
  )

  @spec assert_watch_subscription_step_runtime!(String.t(), String.t()) :: :ok
  defp assert_watch_subscription_step_runtime!(slug, template_key) do
    {:ok, triggers} = Debugger.available_triggers(slug, %{"target" => "watch"})

    exercise_subscription_triggers!(
      slug,
      template_key,
      "watch",
      steppable_watch_triggers(triggers)
    )
  end

  @spec assert_companion_subscription_step_runtime!(String.t(), String.t()) :: :ok
  defp assert_companion_subscription_step_runtime!(slug, template_key) do
    {:ok, triggers} = Debugger.available_triggers(slug, %{"target" => "phone"})

    exercise_subscription_triggers!(
      slug,
      template_key,
      "phone",
      steppable_companion_triggers(triggers)
    )
  end

  @spec steppable_watch_triggers([map()]) :: [map()]
  defp steppable_watch_triggers(triggers) when is_list(triggers) do
    triggers
    |> Enum.filter(fn row ->
      trigger = trigger_row_string(row, :trigger)
      message = trigger_row_string(row, :message)

      trigger_row_active?(row) and trigger != "" and message != "" and
        not SubscriptionTriggerWire.opaque_gateway_trigger?(trigger)
    end)
    |> Enum.sort_by(&watch_trigger_step_priority/1)
  end

  @spec steppable_companion_triggers([map()]) :: [map()]
  defp steppable_companion_triggers(triggers) when is_list(triggers) do
    Enum.filter(triggers, fn row ->
      trigger = trigger_row_string(row, :trigger)
      message = trigger_row_string(row, :message)

      trigger_row_active?(row) and trigger != "" and message != "" and
        CompanionSubscriptionTrigger.companion_trigger?(trigger)
    end)
  end

  @spec watch_trigger_step_priority(map()) :: integer()
  defp watch_trigger_step_priority(row) do
    trigger = trigger_row_string(row, :trigger)
    message = trigger_row_string(row, :message)

    cond do
      SubscriptionTriggerWire.debugger_simulated_payload_trigger?(trigger) -> 0
      tickish_subscription_message?(message) -> 2
      true -> 1
    end
  end

  @spec exercise_subscription_triggers!(String.t(), String.t(), String.t(), [map()]) :: :ok
  defp exercise_subscription_triggers!(_slug, _template_key, _target, []), do: :ok

  defp exercise_subscription_triggers!(slug, template_key, target, rows) do
    case Enum.reduce_while(rows, [], fn row, attempts ->
           case try_subscription_trigger_step(slug, target, row) do
             :ok -> {:halt, :ok}
             {:skip, reason} -> {:cont, [{row, reason} | attempts]}
           end
         end) do
      :ok ->
        :ok

      attempts when is_list(attempts) ->
        details =
          attempts
          |> Enum.reverse()
          |> Enum.map_join("\n", fn {row, reason} ->
            "#{trigger_row_string(row, :trigger)}/#{trigger_row_string(row, :message)}: #{reason}"
          end)

        raise "template #{template_key}: no #{target} subscription step succeeded runtime execution\n#{details}"
    end
  end

  @spec try_subscription_trigger_step(String.t(), String.t(), map()) :: :ok | {:skip, String.t()}
  defp try_subscription_trigger_step(slug, target, row) do
    trigger = trigger_row_string(row, :trigger)
    message = trigger_row_string(row, :message)

    case Debugger.inject_trigger(slug, %{target: target, trigger: trigger, message: message}) do
      {:ok, stepped} ->
        operation_source = step_operation_source(stepped, target)

        cond do
          operation_source == "update_evaluation_failed" ->
            {:skip, "update_evaluation_failed"}

          operation_source in @runtime_step_success_sources ->
            :ok

          is_nil(operation_source) ->
            :ok

          operation_source == "unmapped_message" ->
            {:skip, "unmapped_message"}

          true ->
            {:skip, "unexpected operation_source #{inspect(operation_source)}"}
        end

      {:error, reason} ->
        {:skip, "inject error #{inspect(reason)}"}
    end
  end

  @spec step_operation_source(map(), String.t()) :: String.t() | nil
  defp step_operation_source(stepped, target) do
    surface_key = if target == "phone", do: :companion, else: :watch

    get_in(stepped, [surface_key, :model, "runtime_execution", "operation_source"]) ||
      get_in(stepped, [surface_key, :model, :runtime_execution, :operation_source])
  end

  @spec trigger_row_string(map(), atom()) :: String.t()
  defp trigger_row_string(row, key) when is_map(row) and is_atom(key) do
    row |> TriggerCandidates.row_field(key) |> to_string()
  end

  @spec trigger_row_active?(map()) :: boolean()
  defp trigger_row_active?(row) when is_map(row) do
    case TriggerCandidates.row_field(row, :model_active) do
      false -> false
      "false" -> false
      _ -> true
    end
  end

  @spec tickish_subscription_message?(String.t()) :: boolean()
  defp tickish_subscription_message?(message) when is_binary(message) do
    down = String.downcase(message)

    not String.contains?(down, "datetime") and
      Enum.any?(
        ["tick", "time", "clock", "second", "minute", "hour"],
        &String.contains?(down, &1)
      )
  end

  @doc "Contract checks that every template should satisfy after bootstrap."
  @spec assert_contract!(map(), String.t()) :: :ok
  def assert_contract!(snapshot, template_key)
      when is_map(snapshot) and is_binary(template_key) do
    view_tree_type = Map.get(snapshot, "view_tree_type")
    root_type = get_in(snapshot, ["render_tree", "root_type"])
    preview_ops = Map.get(snapshot, "preview_ops", [])
    diagnostics = Map.get(snapshot, "preview_diagnostics", %{})

    cond do
      view_tree_type == "previewUnavailable" ->
        raise "template #{template_key}: preview unavailable"

      root_type not in ["windowStack", "WindowStack", nil] and not is_binary(root_type) ->
        raise "template #{template_key}: unexpected render root #{inspect(root_type)}"

      preview_ops == [] ->
        raise "template #{template_key}: preview produced no SVG ops"

      Map.get(diagnostics, "status") == "unavailable" ->
        raise "template #{template_key}: preview diagnostics unavailable"

      true ->
        drawable? =
          Enum.any?(preview_ops, fn op ->
            Map.get(op, "kind") not in ["clear", "push_context", "pop_context", nil]
          end)

        output_kinds =
          get_in(snapshot, ["preview_diagnostics", "runtime_view_output_kinds"]) || []

        tree_drawable? =
          get_in(snapshot, ["render_tree", "node_types"])
          |> List.wrap()
          |> Enum.any?(&(&1 not in ["clear", "windowStack", "window", "canvasLayer", ""]))

        unless drawable? or tree_drawable? or template_key in ["starter"] or
                 Enum.any?(output_kinds, &(&1 not in ["clear", "push_context", "pop_context"])) do
          raise "template #{template_key}: preview only has clear/style ops"
        end

        :ok
    end
  end

  @spec snapshot_diff(map(), map()) :: String.t()
  defp snapshot_diff(actual, expected) do
    keys = (Map.keys(actual) ++ Map.keys(expected)) |> Enum.uniq() |> Enum.sort()

    keys
    |> Enum.flat_map(fn key ->
      a = Map.get(actual, key)
      e = Map.get(expected, key)

      if a == e do
        []
      else
        [
          "  #{key}:\n    expected: #{inspect(e, limit: 12)}\n    actual:   #{inspect(a, limit: 12)}"
        ]
      end
    end)
    |> Enum.join("\n")
  end

  @corpus_drain_timeout_ms 45_000

  @spec await_background_idle!(String.t()) :: :ok | {:error, term()}
  defp await_background_idle!(slug) when is_binary(slug) do
    case RuntimeBackgroundDrains.await_idle(slug, @corpus_drain_timeout_ms) do
      :ok -> :ok
      :timeout -> {:error, {:background_drain_timeout, slug}}
    end
  end

  @spec seed_corpus_random!() :: :ok
  defp seed_corpus_random! do
    :rand.seed(:exsss, {0, 0, 1})
    Process.put(:elmx_corpus_fixed_random_int, 42_424_242)
    Application.put_env(:elmx, :corpus_fixed_random_int, 42_424_242)
    :ok
  end
end
