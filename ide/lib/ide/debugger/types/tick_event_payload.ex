defmodule Ide.Debugger.Types.TickEventPayload do
  @moduledoc "Payload for `debugger.tick` batch tick events."

  @type t :: %{
          optional(:target) => String.t() | nil,
          optional(:count) => non_neg_integer(),
          optional(:targets) => [String.t()],
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec from_tick(String.t() | nil, non_neg_integer(), [String.t()]) :: t()
  def from_tick(target, count, targets)
      when is_integer(count) and count >= 0 and is_list(targets) do
    %{target: target, count: count, targets: targets}
  end
end
