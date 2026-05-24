defmodule Ide.Debugger.StepInput do
  @moduledoc """
  Immutable snapshot of inputs for a single debugger runtime step.
  """

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @enforce_keys [:target, :surface, :app_model, :execution_model, :view_tree, :message]
  defstruct [
    :target,
    :surface,
    :app_model,
    :execution_model,
    :view_tree,
    :message,
    :message_value,
    :trigger,
    :message_source
  ]

  @type t :: %__MODULE__{
          target: Types.surface_target(),
          surface: Surface.t(),
          app_model: Types.app_model(),
          execution_model: Types.execution_model(),
          view_tree: Types.view_output_tree(),
          message: String.t(),
          message_value: Types.subscription_payload() | nil,
          trigger: String.t() | nil,
          message_source: String.t() | nil
        }

  @spec from_surface(Types.surface_target(), Surface.t(), String.t(), keyword()) :: t()
  def from_surface(target, %Surface{} = surface, requested_message, opts \\ [])
      when target in [:watch, :companion, :phone] and is_binary(requested_message) and is_list(opts) do
    app_model = Surface.app_model(surface)

    %__MODULE__{
      target: target,
      surface: surface,
      app_model: app_model,
      execution_model: Surface.execution_model(surface),
      view_tree: surface.view_tree || %{},
      message: requested_message,
      message_value: Keyword.get(opts, :message_value),
      trigger: Keyword.get(opts, :trigger),
      message_source: Keyword.get(opts, :message_source)
    }
  end

  @spec with_app_model(t(), Types.app_model()) :: t()
  def with_app_model(%__MODULE__{} = input, app_model) when is_map(app_model) do
    %{input | app_model: app_model, surface: Surface.put_app_model(input.surface, app_model)}
  end

  @spec with_message(t(), String.t()) :: t()
  def with_message(%__MODULE__{} = input, message) when is_binary(message) do
    %{input | message: message}
  end

  @spec with_message_value(t(), Types.subscription_payload() | nil) :: t()
  def with_message_value(%__MODULE__{} = input, message_value) do
    %{input | message_value: message_value}
  end
end

defmodule Ide.Debugger.StepResult do
  @moduledoc """
  Result of a single debugger runtime step: updated session state and surface.
  """

  alias Ide.Debugger.Surface

  @enforce_keys [:state, :surface]
  defstruct [:state, :surface]

  @type t :: %__MODULE__{
          state: map(),
          surface: Surface.t()
        }

  @spec new(map(), Surface.t()) :: t()
  def new(state, %Surface{} = surface) when is_map(state) do
    %__MODULE__{state: state, surface: surface}
  end

  @spec state(t()) :: map()
  def state(%__MODULE__{state: state}), do: state
end
