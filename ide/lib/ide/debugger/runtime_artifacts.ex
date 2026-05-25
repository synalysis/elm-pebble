defmodule Ide.Debugger.RuntimeArtifacts do
  @moduledoc """
  Shared helpers for debugger runtime model artifacts (`elm_introspect`, Core IR, resource indices).

  Centralizes decoding and evaluation-context construction so watch/companion models stay
  consistent across the debugger session, semantic executor requests, and preview rendering.
  """

  alias ElmEx.CoreIR
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Projects
  alias Ide.Resources.ResourceStore

  @type app_model :: Types.app_model()
  @type shell :: Types.shell()
  @type execution_model :: Types.execution_model()
  @type inner_runtime_model :: Types.inner_runtime_model()

  @spec inner_runtime_model(app_model() | execution_model() | map()) :: inner_runtime_model()
  def inner_runtime_model(model) when is_map(model) do
    case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
      nested when is_map(nested) -> nested
      _ -> %{}
    end
  end

  def inner_runtime_model(_model), do: %{}

  @spec app_model(map()) :: app_model()
  def app_model(model) when is_map(model), do: strip_shell_artifacts(model)
  def app_model(_model), do: %{}

  @shell_artifact_keys [
    "vector_resource_indices",
    "bitmap_resource_indices",
    "elm_introspect",
    "elm_executor_core_ir",
    "elm_executor_core_ir_b64",
    "elm_executor_metadata"
  ]

  @spec shell_artifact_keys() :: [String.t()]
  def shell_artifact_keys, do: @shell_artifact_keys

  @spec strip_shell_artifacts(map()) :: map()
  def strip_shell_artifacts(model) when is_map(model) do
    Map.drop(model, shell_artifact_drop_keys())
  end

  def strip_shell_artifacts(_model), do: %{}

  @spec take_shell_artifacts(map()) :: map()
  def take_shell_artifacts(model) when is_map(model) do
    keys = shell_artifact_drop_keys()

    model
    |> Enum.filter(fn {key, value} -> key in keys and not is_nil(value) end)
    |> Map.new()
  end

  def take_shell_artifacts(_model), do: %{}

  @spec partition_fields(map()) :: {map(), map()}
  def partition_fields(fields) when is_map(fields) do
    {strip_shell_artifacts(fields), take_shell_artifacts(fields)}
  end

  def partition_fields(_fields), do: {%{}, %{}}

  @spec shell_map(map()) :: shell()
  def shell_map(%Surface{} = surface), do: shell_map(Surface.to_map(surface))

  def shell_map(surface) when is_map(surface) do
    explicit = Map.get(surface, :shell) || Map.get(surface, "shell") || %{}
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}

    take_shell_artifacts(surface)
    |> Map.merge(take_shell_artifacts(model))
    |> Map.merge(if is_map(explicit), do: explicit, else: %{})
  end

  def shell_map(_surface), do: %{}

  @spec public_model(map()) :: map()
  def public_model(model) when is_map(model) do
    nested = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)

    if is_map(nested) and map_size(nested) > 0 do
      nested
    else
      strip_shell_artifacts(model)
    end
  end

  def public_model(_model), do: %{}

  @spec execution_model(map()) :: map()
  def execution_model(%Surface{} = surface), do: Surface.execution_model(surface)

  def execution_model(surface) when is_map(surface) do
    surface = normalize_surface(surface)
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}
    Map.merge(shell_map(surface), strip_shell_artifacts(model))
  end

  def execution_model(_surface), do: %{}

  @spec introspect(map()) :: map() | nil
  def introspect(%Surface{} = surface), do: introspect(Surface.to_map(surface))

  def introspect(surface_or_execution_model) when is_map(surface_or_execution_model) do
    shell_map(surface_or_execution_model)
    |> Map.get("elm_introspect")
    |> case do
      value when is_map(value) -> value
      _ -> nil
    end
  end

  def introspect(_), do: nil

  @spec require_introspect(map()) :: Types.elm_introspect()
  def require_introspect(surface_or_execution_model) when is_map(surface_or_execution_model) do
    case introspect(surface_or_execution_model) do
      ei when is_map(ei) -> ei
      _ -> %{}
    end
  end

  def require_introspect(_), do: %{}

  @spec normalize_surface(map()) :: map()
  def normalize_surface(%Surface{} = surface), do: normalize_surface(Surface.to_map(surface))

  def normalize_surface(surface) when is_map(surface) do
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}
    shell = Map.get(surface, :shell) || Map.get(surface, "shell") || %{}
    {app, legacy_shell} = partition_fields(model)

    surface
    |> Map.put(:model, app)
    |> Map.put(:shell, Map.merge(shell, legacy_shell))
  end

  def normalize_surface(surface), do: surface

  @spec decode_core_ir(execution_model() | map()) :: Types.core_ir()
  def decode_core_ir(model) when is_map(model) do
    case Map.get(model, "elm_executor_core_ir") do
      %CoreIR{} = value ->
        value

      value when is_map(value) ->
        value

      _ ->
        case Map.get(model, "elm_executor_core_ir_b64") do
          encoded when is_binary(encoded) and encoded != "" ->
            with {:ok, binary} <- Base.decode64(encoded) do
              case :erlang.binary_to_term(binary, [:safe]) do
                %CoreIR{} = value -> value
                value when is_map(value) -> value
                _ -> nil
              end
            else
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  def decode_core_ir(_model), do: nil

  @spec module_name(execution_model() | map()) :: String.t()
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

  @spec vector_resource_indices(execution_model() | map()) :: map()
  def vector_resource_indices(model) when is_map(model) do
    Map.get(model, "vector_resource_indices") ||
      get_in(model, ["runtime_model", "vector_resource_indices"]) ||
      %{}
  end

  def vector_resource_indices(_model), do: %{}

  @spec bitmap_resource_indices(execution_model() | map()) :: map()
  def bitmap_resource_indices(model) when is_map(model) do
    Map.get(model, "bitmap_resource_indices") ||
      get_in(model, ["runtime_model", "bitmap_resource_indices"]) ||
      %{}
  end

  def bitmap_resource_indices(_model), do: %{}

  @spec execution_artifacts(execution_model() | map()) :: ArtifactTypes.t()
  def execution_artifacts(model) when is_map(model) do
    metadata = Map.get(model, "elm_executor_metadata")
    core_ir = decode_core_ir(model)

    %{}
    |> maybe_put_artifact(:elm_executor_metadata, metadata)
    |> maybe_put_artifact(:elm_executor_core_ir, core_ir)
  end

  def execution_artifacts(_model), do: %{}

  @spec core_ir_eval_context(execution_model() | map(), keyword()) :: map()
  def core_ir_eval_context(model, extras \\ [])

  def core_ir_eval_context(model, extras) when is_map(model) and is_list(extras) do
    module = module_name(model)
    vector_indices = vector_resource_indices(model)
    bitmap_indices = bitmap_resource_indices(model)

    base =
      case decode_core_ir(model) do
        core_ir when is_map(core_ir) ->
          %{
            functions: ElmExecutor.Runtime.CoreIREvaluator.index_functions(core_ir),
            record_aliases: ElmExecutor.Runtime.CoreIREvaluator.index_record_aliases(core_ir),
            constructor_tags: ElmExecutor.Runtime.CoreIREvaluator.index_constructor_tags(core_ir),
            module: module,
            source_module: module
          }

        _ ->
          %{module: module, source_module: module}
      end

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

    Enum.reduce(extras, base, fn
      {key, value}, acc when is_atom(key) and not is_nil(value) -> Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  def core_ir_eval_context(_model, _extras), do: %{}

  @spec merge_shell_artifacts(map(), map()) :: map()
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

  @spec put_vector_resource_indices_on_request(map(), map()) :: map()
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

  @spec put_bitmap_resource_indices_on_request(map(), map()) :: map()
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

  @spec vector_resource_indices_for_project(String.t()) :: map()
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

  @spec bitmap_resource_indices_for_project(String.t()) :: map()
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

  @spec maybe_put_artifact(map(), atom(), map() | nil) :: map()
  defp maybe_put_artifact(map, key, value)
       when is_map(map) and is_atom(key) and is_map(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_artifact(map, _key, _value) when is_map(map), do: map

  @spec shell_artifact_drop_keys() :: [String.t() | atom()]
  defp shell_artifact_drop_keys do
    @shell_artifact_keys ++ Enum.map(@shell_artifact_keys, &String.to_atom/1)
  end
end
