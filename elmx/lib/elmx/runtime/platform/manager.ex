defmodule Elmx.Runtime.Platform.Manager do
  @moduledoc false

  alias Elmx.Types

  @type manager :: Types.manager()

  @spec tag(integer()) :: manager()
  def tag(n) when is_integer(n), do: %{"$" => n}

  @spec batch([Types.manager_batch_item()]) :: manager()
  def batch(items) when is_list(items), do: %{"$" => 2, "m" => items}

  @spec port(String.t(), Types.wire_value() | Types.elm_msg() | manager()) :: manager()
  def port(key, leaf) when is_binary(key), do: %{"$" => 1, "k" => key, "l" => leaf}

  @spec map(Types.elm_hof(), manager() | Types.wire_cmd_input()) :: manager()
  def map(fun, inner), do: %{"$" => 3, "n" => fun, "o" => inner}
end
