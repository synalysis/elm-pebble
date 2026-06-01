defmodule Elmx.Runtime.Core.Task do
  @moduledoc false

  @spec succeed(term()) :: {:Ok, term()}
  def succeed(value), do: {:Ok, value}

  @spec fail(term()) :: {:Err, term()}
  def fail(error), do: {:Err, error}
end
