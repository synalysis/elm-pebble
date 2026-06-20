defmodule Elmx.Runtime.Platform.Manager do
  @moduledoc false

  @type manager :: map()

  @spec tag(integer()) :: manager()
  def tag(n) when is_integer(n), do: %{"$" => n}

  @spec batch([term()]) :: manager()
  def batch(items) when is_list(items), do: %{"$" => 2, "m" => items}

  @spec port(String.t(), term()) :: manager()
  def port(key, leaf) when is_binary(key), do: %{"$" => 1, "k" => key, "l" => leaf}

  @spec map(term(), term()) :: manager()
  def map(fun, inner), do: %{"$" => 3, "n" => fun, "o" => inner}
end
