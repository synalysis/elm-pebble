defmodule Ide.Debugger.RuntimeArtifacts do
  @moduledoc """
  Shared helpers for debugger runtime model artifacts (`debugger_contract`, `elmx`, resource indices).

  Centralizes shell artifact handling so watch/companion models stay consistent across
  debugger sessions, runtime executor requests, and preview rendering.
  """

  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Projects
  alias Ide.Resources.ResourceStore

  @type app_model :: Types.app_model()
  @type shell :: Types.shell()
  @type execution_model :: Types.execution_model()
  @type inner_runtime_model :: Types.inner_runtime_model()

  @spec inner_runtime_model(app_model() | execution_model()) :: inner_runtime_model()
  def inner_runtime_model(model) when is_map(model) do
    case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
      nested when is_map(nested) -> nested
      _ -> %{}
    end
  end

  def inner_runtime_model(_model), do: %{}

  @spec app_model(app_model()) :: app_model()
  def app_model(model) when is_map(model), do: strip_shell_artifacts(model)
  def app_model(_model), do: %{}

  @shell_artifact_keys [
    "vector_resource_indices",
    "bitmap_resource_indices",
    "animation_resource_indices",
    "debugger_contract",
    "debugger_contract_b64",
    "debugger_contract_version",
    "elm_introspect",
    "elmx_manifest",
    "elmx_revision"
  ]

  @spec shell_artifact_keys() :: [String.t()]
  def shell_artifact_keys, do: @shell_artifact_keys

  @doc false
  @spec normalize_contract_shell(Types.wire_map()) :: Types.wire_map()
  def normalize_contract_shell(shell) when is_map(shell), do: promote_legacy_contract_shell(shell)
  def normalize_contract_shell(shell), do: shell

  @spec strip_shell_artifacts(app_model()) :: app_model()
  def strip_shell_artifacts(model) when is_map(model) do
    Map.drop(model, shell_artifact_drop_keys())
  end

  def strip_shell_artifacts(_model), do: %{}

  @spec take_shell_artifacts(app_model()) :: Types.wire_map()
  def take_shell_artifacts(model) when is_map(model) do
    keys = shell_artifact_drop_keys()

    model
    |> Enum.filter(fn {key, value} -> key in keys and not is_nil(value) end)
    |> Map.new()
    |> promote_legacy_contract_shell()
  end

  def take_shell_artifacts(_model), do: %{}

  @spec partition_fields(app_model()) :: {app_model(), Types.wire_map()}
  def partition_fields(fields) when is_map(fields) do
    {strip_shell_artifacts(fields), take_shell_artifacts(fields)}
  end

  def partition_fields(_fields), do: {%{}, %{}}

  @spec shell_map(Surface.t() | Surface.surface_map()) :: shell()
  def shell_map(%Surface{model: model, shell: explicit}) do
    take_shell_artifacts(%{model: model, shell: explicit})
    |> Map.merge(take_shell_artifacts(model))
    |> Map.merge(if is_map(explicit), do: explicit, else: %{})
    |> promote_legacy_contract_shell()
  end

  def shell_map(surface) when is_map(surface) do
    explicit = Map.get(surface, :shell) || Map.get(surface, "shell") || %{}
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}

    take_shell_artifacts(surface)
    |> Map.merge(take_shell_artifacts(model))
    |> Map.merge(if is_map(explicit), do: explicit, else: %{})
    |> promote_legacy_contract_shell()
  end

  def shell_map(_surface), do: %{}

  @spec public_model(app_model()) :: inner_runtime_model()
  def public_model(model) when is_map(model) do
    nested = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)

    if is_map(nested) and map_size(nested) > 0 do
      nested
    else
      strip_shell_artifacts(model)
    end
  end

  def public_model(_model), do: %{}

  @runtime_preview_envelope_keys [
    "runtime_model",
    "runtime_view_output",
    "runtime_view_output_model_sha256",
    "runtime_view_tree",
    "runtime_view_tree_source",
    "runtime_last_message",
    "runtime_message_source",
    "runtime_message_cursor",
    "runtime_known_messages",
    "runtime_update_branches",
    "runtime_view_tree_sha256",
    "runtime_model_sha256",
    "runtime_model_source",
    "runtime_execution_mode",
    "runtime_execution",
    "elmc_check",
    "elmc_compile",
    "elmc_diagnostic_preview"
  ]

  @spec preview_runtime_model(app_model()) :: app_model()
  def preview_runtime_model(model) when is_map(model) do
    inner = inner_runtime_model(model)
    launch_context = Map.get(model, "launch_context") || Map.get(model, :launch_context)

    model
    |> strip_shell_artifacts()
    |> Map.drop(runtime_preview_envelope_drop_keys())
    |> Map.merge(inner)
    |> maybe_merge_launch_context_preview_fields(launch_context)
  end

  def preview_runtime_model(_model), do: %{}

  defp maybe_merge_launch_context_preview_fields(model, launch_context)
       when is_map(launch_context) and map_size(launch_context) > 0 do
    Map.merge(model, RuntimeSurfaces.launch_context_screen_fields(launch_context))
  end

  defp maybe_merge_launch_context_preview_fields(model, _launch_context), do: model

  @spec execution_model(Surface.t() | Surface.surface_map()) :: execution_model()
  def execution_model(%Surface{} = surface), do: Surface.execution_model(surface)

  def execution_model(surface) when is_map(surface) do
    surface = normalize_surface(surface)
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}
    Map.merge(shell_map(surface), strip_shell_artifacts(model))
  end

  def execution_model(_surface), do: %{}

  @spec introspect(Surface.t() | Surface.surface_map() | execution_model()) ::
          Types.elm_introspect() | nil
  def introspect(%Surface{} = surface) do
    surface |> shell_map() |> Ide.Debugger.CompileContract.from_shell()
  end

  def introspect(surface_or_execution_model) when is_map(surface_or_execution_model) do
    shell_map(surface_or_execution_model)
    |> Ide.Debugger.CompileContract.from_shell()
  end

  def introspect(_), do: nil

  @spec require_introspect(Surface.t() | Surface.surface_map() | execution_model()) ::
          Types.elm_introspect()
  def require_introspect(surface_or_execution_model) when is_map(surface_or_execution_model) do
    case introspect(surface_or_execution_model) do
      ei when is_map(ei) -> ei
      _ -> %{}
    end
  end

  def require_introspect(_), do: %{}

  @spec normalize_surface(Surface.t() | Surface.surface_map()) :: Surface.surface_map()
  def normalize_surface(%Surface{model: model, shell: shell} = surface) do
    normalize_surface(%{
      model: model,
      shell: shell,
      view_tree: surface.view_tree,
      last_message: surface.last_message,
      protocol_messages: surface.protocol_messages
    })
  end

  def normalize_surface(surface) when is_map(surface) do
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}
    shell = Map.get(surface, :shell) || Map.get(surface, "shell") || %{}
    {app, legacy_shell} = partition_fields(model)

    surface
    |> Map.put(:model, app)
    |> Map.put(:shell, Map.merge(shell, legacy_shell))
  end

  def normalize_surface(surface), do: surface

  @spec versioned_elmx_artifacts?(execution_model()) :: boolean()
  def versioned_elmx_artifacts?(model) when is_map(model) do
    manifest = Map.get(model, "elmx_manifest") || Map.get(model, :elmx_manifest)
    revision = Map.get(model, "elmx_revision") || Map.get(model, :elmx_revision)

    is_map(manifest) and Map.get(manifest, "contract") == "elmx.runtime_executor.v1" and
      is_binary(revision) and revision != ""
  end

  def versioned_elmx_artifacts?(_), do: false

  @spec module_name(execution_model()) :: String.t()
  def module_name(model) when is_map(model) do
    model
    |> require_introspect()
    |> Map.get("module")
    |> case do
      name when is_binary(name) and name != "" -> name
      _ -> "Main"
    end
  end

  def module_name(_model), do: "Main"

  @spec entry_module_name(execution_model()) :: String.t() | nil
  def entry_module_name(model) when is_map(model) do
    case get_in(model, ["elmx_manifest", "entry_module"]) ||
           get_in(model, [:elmx_manifest, "entry_module"]) do
      %{"entry_module" => name} when is_binary(name) and name != "" -> name
      %{entry_module: name} when is_binary(name) and name != "" -> name
      name when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  def entry_module_name(_model), do: nil

  @spec vector_resource_indices(execution_model()) :: ArtifactTypes.resource_indices()
  def vector_resource_indices(model) when is_map(model) do
    Map.get(model, "vector_resource_indices") ||
      get_in(model, ["runtime_model", "vector_resource_indices"]) ||
      %{}
  end

  def vector_resource_indices(_model), do: %{}

  @spec bitmap_resource_indices(execution_model()) :: ArtifactTypes.resource_indices()
  def bitmap_resource_indices(model) when is_map(model) do
    Map.get(model, "bitmap_resource_indices") ||
      get_in(model, ["runtime_model", "bitmap_resource_indices"]) ||
      %{}
  end

  def bitmap_resource_indices(_model), do: %{}

  @spec animation_resource_indices(execution_model()) :: ArtifactTypes.resource_indices()
  def animation_resource_indices(model) when is_map(model) do
    Map.get(model, "animation_resource_indices") ||
      get_in(model, ["runtime_model", "animation_resource_indices"]) ||
      %{}
  end

  def animation_resource_indices(_model), do: %{}

  @spec execution_artifacts(execution_model()) :: ArtifactTypes.t()
  def execution_artifacts(model) when is_map(model) do
    elmx_manifest = wire_field(model, "elmx_manifest")
    elmx_revision = wire_field(model, "elmx_revision")
    elmx_compile_error = wire_field(model, "elmx_compile_error")
    elmx_compile_error_message = wire_field(model, "elmx_compile_error_message")

    %{}
    |> maybe_put_artifact(:elmx_manifest, elmx_manifest)
    |> maybe_put_artifact(:elmx_revision, elmx_revision)
    |> maybe_put_artifact(:elmx_compile_error, elmx_compile_error)
    |> maybe_put_artifact(:elmx_compile_error_message, elmx_compile_error_message)
  end

  def execution_artifacts(_model), do: %{}

  @spec eval_context(execution_model(), keyword()) :: Types.http_eval_context()
  def eval_context(model, extras \\ [])

  def eval_context(model, extras) when is_map(model) and is_list(extras) do
    module = entry_module_name(model) || module_name(model)
    vector_indices = vector_resource_indices(model)
    bitmap_indices = bitmap_resource_indices(model)
    animation_indices = animation_resource_indices(model)

    base = %{module: module, source_module: module}

    base =
      if map_size(vector_indices) > 0 do
        Map.put(base, :vector_resource_indices, vector_indices)
      else
        base
      end

    base =
      if map_size(bitmap_indices) > 0 do
        Map.put(base, :bitmap_resource_indices, bitmap_indices)
      else
        base
      end

    base =
      if map_size(animation_indices) > 0 do
        Map.put(base, :animation_resource_indices, animation_indices)
      else
        base
      end

    Enum.reduce(extras, base, fn
      {key, value}, acc when is_atom(key) and not is_nil(value) -> Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  def eval_context(_model, _extras), do: %{}

  @spec merge_shell_artifacts(execution_model(), shell()) :: execution_model()
  def merge_shell_artifacts(base, shell) when is_map(base) and is_map(shell) do
    Enum.reduce(@shell_artifact_keys, base, fn key, acc ->
      case Map.get(shell, key) do
        value when not is_nil(value) -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
  end

  def merge_shell_artifacts(base, _shell) when is_map(base), do: base
  def merge_shell_artifacts(_base, _shell), do: %{}

  @type request_attrs :: ArtifactTypes.t() | map()

  @spec put_vector_resource_indices_on_request(request_attrs(), Types.execution_model()) ::
          request_attrs()
  def put_vector_resource_indices_on_request(request, model)
      when is_map(request) and is_map(model) do
    case vector_resource_indices(model) do
      indices when map_size(indices) > 0 ->
        Map.put(request, :vector_resource_indices, indices)

      _ ->
        request
    end
  end

  def put_vector_resource_indices_on_request(request, _model) when is_map(request), do: request
  def put_vector_resource_indices_on_request(request, _model), do: request

  @spec put_bitmap_resource_indices_on_request(request_attrs(), Types.execution_model()) ::
          request_attrs()
  def put_bitmap_resource_indices_on_request(request, model)
      when is_map(request) and is_map(model) do
    case bitmap_resource_indices(model) do
      indices when map_size(indices) > 0 ->
        Map.put(request, :bitmap_resource_indices, indices)

      _ ->
        request
    end
  end

  def put_bitmap_resource_indices_on_request(request, _model) when is_map(request), do: request
  def put_bitmap_resource_indices_on_request(request, _model), do: request

  @spec put_animation_resource_indices_on_request(request_attrs(), Types.execution_model()) ::
          request_attrs()
  def put_animation_resource_indices_on_request(request, model)
      when is_map(request) and is_map(model) do
    case animation_resource_indices(model) do
      indices when map_size(indices) > 0 ->
        Map.put(request, :animation_resource_indices, indices)

      _ ->
        request
    end
  end

  def put_animation_resource_indices_on_request(request, _model) when is_map(request), do: request
  def put_animation_resource_indices_on_request(request, _model), do: request

  @spec vector_resource_indices_for_project(String.t()) :: ArtifactTypes.resource_indices()
  def vector_resource_indices_for_project(project_slug) when is_binary(project_slug) do
    with %Projects.Project{} = project <- Projects.get_project_by_scope_key(project_slug),
         {:ok, entries} <- ResourceStore.list_vectors(project) do
      entries
      |> Enum.with_index(1)
      |> Map.new(fn {row, index} -> {row.ctor, index} end)
    else
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  @spec bitmap_resource_indices_for_project(String.t()) :: ArtifactTypes.resource_indices()
  def bitmap_resource_indices_for_project(project_slug) when is_binary(project_slug) do
    with %Projects.Project{} = project <- Projects.get_project_by_scope_key(project_slug),
         {:ok, entries} <- ResourceStore.list(project) do
      entries
      |> Enum.with_index(1)
      |> Map.new(fn {row, index} -> {row.ctor, index} end)
    else
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  @spec animation_resource_indices_for_project(String.t()) :: ArtifactTypes.resource_indices()
  def animation_resource_indices_for_project(project_slug) when is_binary(project_slug) do
    with %Projects.Project{} = project <- Projects.get_project_by_scope_key(project_slug),
         {:ok, entries} <- Ide.Resources.ResourceStore.list_animations(project) do
      entries
      |> Enum.with_index(1)
      |> Map.new(fn {row, index} -> {row.ctor, index} end)
    else
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  @spec wire_field(Types.wire_map(), String.t()) :: Types.wire_input() | nil
  defp wire_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  @spec maybe_put_artifact(ArtifactTypes.t(), atom(), Types.wire_input() | nil) ::
          ArtifactTypes.t()
  defp maybe_put_artifact(map, key, value)
       when is_map(map) and is_atom(key) and is_map(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_artifact(map, key, value)
       when is_map(map) and is_atom(key) and not is_nil(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_artifact(map, _key, _value) when is_map(map), do: map

  @spec promote_legacy_contract_shell(Types.wire_map()) :: Types.wire_map()
  defp promote_legacy_contract_shell(shell) when is_map(shell) do
    contract =
      Map.get(shell, "debugger_contract") || Map.get(shell, :debugger_contract) ||
        Map.get(shell, "elm_introspect") || Map.get(shell, :elm_introspect)

    case contract do
      c when is_map(c) ->
        shell
        |> Map.drop(["elm_introspect", :elm_introspect])
        |> Map.put("debugger_contract", c)

      _ ->
        shell
    end
  end

  @spec shell_artifact_drop_keys() :: [String.t() | atom()]
  defp shell_artifact_drop_keys do
    @shell_artifact_keys ++ Enum.map(@shell_artifact_keys, &String.to_atom/1)
  end

  @spec runtime_preview_envelope_drop_keys() :: [String.t() | atom()]
  defp runtime_preview_envelope_drop_keys do
    @runtime_preview_envelope_keys ++ Enum.map(@runtime_preview_envelope_keys, &String.to_atom/1)
  end
end
