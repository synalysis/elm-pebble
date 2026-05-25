defmodule Ide.Debugger.Surface do
  @moduledoc """
  Typed debugger surface: app `model`, debugger `shell`, and optional view metadata.

  ## Which accessor to use

  - `app_model/1` — user-facing Elm state stored on the surface (no shell artifacts).
  - `execution_model/1` — app model merged with shell; use for runtime stepping and introspect.
  - `introspect/1` — Elm introspect payload from shell only.
  - `from_state/2` + `put_in_state/3` — read/write surfaces on debugger session state.

  Prefer these helpers over `get_in(state, [target, :model])` or raw `Map.get(..., "elm_introspect")`.
  """

  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types

  @enforce_keys [:model, :shell]
  defstruct [:model, :shell, :view_tree, :last_message, :protocol_messages]

  @type t :: %__MODULE__{
          model: Types.app_model(),
          shell: Types.shell(),
          view_tree: ViewTreeNode.view_tree() | ViewTreeNode.t() | nil,
          last_message: String.t() | nil,
          protocol_messages: list() | nil
        }

  @type surface_map :: %{
          optional(:model) => map(),
          optional(:shell) => map(),
          optional(:view_tree) => Types.view_output_tree(),
          optional(:last_message) => String.t() | nil,
          optional(:protocol_messages) => list(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_map(map()) :: t()
  def from_map(surface) when is_map(surface) do
    normalized = RuntimeArtifacts.normalize_surface(surface)

    %__MODULE__{
      model: Map.get(normalized, :model) || %{},
      shell: Map.get(normalized, :shell) || %{},
      view_tree: Map.get(normalized, :view_tree) || Map.get(normalized, "view_tree"),
      last_message: Map.get(normalized, :last_message) || Map.get(normalized, "last_message"),
      protocol_messages:
        Map.get(normalized, :protocol_messages) || Map.get(normalized, "protocol_messages")
    }
  end

  def from_map(_surface), do: %__MODULE__{model: %{}, shell: %{}}

  @spec from_state(map(), Types.surface_target()) :: t()
  def from_state(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    state |> Map.get(target, %{}) |> from_map()
  end

  @spec put_in_state(map(), Types.surface_target(), t() | surface_map()) :: map()
  def put_in_state(state, target, surface)
      when is_map(state) and target in [:watch, :companion, :phone] do
    Map.put(state, target, to_map(from_map(surface)))
  end

  @spec update_in_state(map(), Types.surface_target(), (t() -> t())) :: map()
  def update_in_state(state, target, fun)
      when is_map(state) and target in [:watch, :companion, :phone] and is_function(fun, 1) do
    state |> from_state(target) |> fun.() |> then(&put_in_state(state, target, &1))
  end

  @spec to_map(t()) :: surface_map()
  def to_map(%__MODULE__{} = surface) do
    %{
      model: surface.model,
      shell: surface.shell,
      view_tree: surface.view_tree,
      last_message: surface.last_message,
      protocol_messages: surface.protocol_messages
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

  @spec merge_app_model(t(), map()) :: t()
  def merge_app_model(%__MODULE__{} = surface, patch) when is_map(patch) do
    %{surface | model: Map.merge(surface.model, patch)}
  end

  @spec put_shell(t(), map()) :: t()
  def put_shell(%__MODULE__{} = surface, shell) when is_map(shell) do
    %{surface | shell: shell}
  end

  @spec put_view_tree(t(), map() | nil) :: t()
  def put_view_tree(%__MODULE__{} = surface, view_tree) do
    %{surface | view_tree: view_tree}
  end

  @spec put_last_message(t(), String.t() | nil) :: t()
  def put_last_message(%__MODULE__{} = surface, message) do
    %{surface | last_message: message}
  end
end
