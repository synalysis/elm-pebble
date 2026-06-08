defmodule Ide.Debugger.RuntimeExecutor.Request do
  @moduledoc """
  Builds validated runtime executor requests from debugger surfaces.

  `validate!/1` checks shape (introspect, model). `validate_execution_ready!/1` also
  requires compiled `elmx` artifacts — used by `RuntimeExecutor.execute/1` on `%Request{}`.
  """

  alias ElmEx.DebuggerContract.Payload
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @enforce_keys [
    :source_root,
    :rel_path,
    :source,
    :introspect,
    :current_model,
    :current_view_tree
  ]
  defstruct [
    :source_root,
    :rel_path,
    :source,
    :introspect,
    :current_model,
    :current_view_tree,
    :message,
    :message_value,
    :update_branches,
    :elmx_manifest,
    :elmx_revision,
    :elmx_compile_error,
    :elmx_compile_error_message,
    :vector_resource_indices,
    :bitmap_resource_indices,
    :animation_resource_indices
  ]

  @type t :: %__MODULE__{
          source_root: String.t(),
          rel_path: String.t() | nil,
          source: String.t(),
          introspect: Payload.wire_payload(),
          current_model: Types.app_model(),
          current_view_tree: Types.view_output_tree(),
          message: String.t() | nil,
          message_value: Types.protocol_message_wire_value() | nil,
          update_branches: [String.t()] | nil,
          elmx_manifest: Types.elmx_manifest() | nil,
          elmx_revision: String.t() | nil,
          elmx_compile_error: term() | nil,
          elmx_compile_error_message: String.t() | nil,
          vector_resource_indices: ArtifactTypes.resource_indices() | nil,
          bitmap_resource_indices: ArtifactTypes.resource_indices() | nil,
          animation_resource_indices: ArtifactTypes.resource_indices() | nil
        }

  @type wire_map :: ExecutorTypes.execution_input_map()

  @spec build(keyword()) :: t()
  def build(opts) when is_list(opts) do
    surface = Keyword.fetch!(opts, :surface)
    execution_model = Surface.execution_model(surface)
    message = Keyword.get(opts, :message)

    app_model = Surface.app_model(surface)

    introspect = RuntimeArtifacts.require_introspect(execution_model)

    attrs = %{
      source_root: Keyword.get(opts, :source_root, "watch"),
      rel_path: Map.get(app_model, "last_path"),
      source: Map.get(app_model, "last_source") || "",
      introspect: introspect,
      current_model: app_model,
      current_view_tree: Keyword.get(opts, :view_tree) || surface.view_tree || %{},
      message: message,
      message_value: Keyword.get(opts, :message_value),
      update_branches: Keyword.get(opts, :update_branches)
    }

    attrs
    |> Map.merge(RuntimeArtifacts.execution_artifacts(execution_model))
    |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
    |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)
    |> RuntimeArtifacts.put_animation_resource_indices_on_request(execution_model)
    |> then(&struct!(__MODULE__, &1))
    |> validate!()
  end

  @spec to_map(t()) :: wire_map()
  def to_map(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec validate!(t() | wire_map()) :: t()
  def validate!(%__MODULE__{} = request) do
    unless is_map(request.introspect) do
      raise ArgumentError, "runtime executor request requires introspect"
    end

    unless is_map(request.current_model) do
      raise ArgumentError, "runtime executor request requires current_model"
    end

    request
  end

  def validate!(request) when is_map(request) do
    request
    |> Map.new(fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
    end)
    |> then(&struct!(__MODULE__, &1))
    |> validate!()
  rescue
    ArgumentError -> validate!(Map.new(request))
  end

  @spec validate_execution_ready!(t() | wire_map()) :: t()
  def validate_execution_ready!(request) do
    request = validate!(request)

    unless elmx_execution_ready?(request) do
      raise ArgumentError, "runtime executor request requires elmx_manifest and elmx_revision"
    end

    request
  end

  @spec elmx_execution_ready?(t()) :: boolean()
  defp elmx_execution_ready?(%__MODULE__{} = request) do
    RuntimeArtifacts.versioned_elmx_artifacts?(%{
      "elmx_manifest" => request.elmx_manifest,
      "elmx_revision" => request.elmx_revision
    })
  end
end
