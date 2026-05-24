defmodule Ide.Debugger.Surface do
  @moduledoc """
  Typed debugger surface: app `model`, debugger `shell`, and optional view metadata.

  Use `execution_model/1` (shell merged with stripped app model) for runtime execution,
  protocol resolution, and introspect lookups. Use `app_model/1` for user-facing state only.
  """

  alias Ide.Debugger.RuntimeArtifacts

  @enforce_keys [:model, :shell]
  defstruct [:model, :shell, :view_tree, :last_message]

  @type t :: %__MODULE__{
          model: RuntimeArtifacts.app_model(),
          shell: RuntimeArtifacts.shell(),
          view_tree: map() | nil,
          last_message: term()
        }

  @type surface_map :: %{
          optional(:model) => map(),
          optional(:shell) => map(),
          optional(:view_tree) => map(),
          optional(:last_message) => term(),
          optional(String.t()) => term()
        }

  @spec from_map(map()) :: t()
  def from_map(surface) when is_map(surface) do
    normalized = RuntimeArtifacts.normalize_surface(surface)

    %__MODULE__{
      model: Map.get(normalized, :model) || %{},
      shell: Map.get(normalized, :shell) || %{},
      view_tree: Map.get(normalized, :view_tree) || Map.get(normalized, "view_tree"),
      last_message: Map.get(normalized, :last_message) || Map.get(normalized, "last_message")
    }
  end

  def from_map(_surface), do: %__MODULE__{model: %{}, shell: %{}}

  @spec to_map(t()) :: surface_map()
  def to_map(%__MODULE__{} = surface) do
    %{
      model: surface.model,
      shell: surface.shell,
      view_tree: surface.view_tree,
      last_message: surface.last_message
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec app_model(t() | map()) :: RuntimeArtifacts.app_model()
  def app_model(%__MODULE__{model: model}), do: model

  def app_model(surface) when is_map(surface), do: from_map(surface).model

  @spec shell(t() | map()) :: RuntimeArtifacts.shell()
  def shell(%__MODULE__{shell: shell}), do: shell

  def shell(surface) when is_map(surface), do: from_map(surface).shell

  @spec execution_model(t() | map()) :: RuntimeArtifacts.execution_model()
  def execution_model(%__MODULE__{} = surface), do: RuntimeArtifacts.execution_model(to_map(surface))

  def execution_model(surface) when is_map(surface), do: RuntimeArtifacts.execution_model(surface)

  @spec introspect(t() | map()) :: map() | nil
  def introspect(surface), do: RuntimeArtifacts.introspect(surface)

  @spec introspect!(t() | map()) :: map()
  def introspect!(surface) do
    case introspect(surface) do
      ei when is_map(ei) -> ei
      _ -> %{}
    end
  end

  @spec put_app_model(t(), map()) :: t()
  def put_app_model(%__MODULE__{} = surface, model) when is_map(model) do
    %{surface | model: model}
  end

  @spec put_shell(t(), map()) :: t()
  def put_shell(%__MODULE__{} = surface, shell) when is_map(shell) do
    %{surface | shell: shell}
  end
end
