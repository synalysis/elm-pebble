defmodule Ide.Test.TimelineAssertions do
  @moduledoc false

  @spec has_entry?([{String.t(), String.t(), String.t() | nil}], String.t(), String.t(), String.t()) ::
          boolean()
  def has_entry?(timeline, target, ctor_prefix, source)
      when is_list(timeline) and is_binary(target) and is_binary(ctor_prefix) and is_binary(source) do
    Enum.any?(timeline, fn
      {^target, msg, ^source} when is_binary(msg) ->
        String.starts_with?(msg, ctor_prefix)

      _ ->
        false
    end)
  end
end
