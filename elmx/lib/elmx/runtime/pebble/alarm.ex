defmodule Elmx.Runtime.Pebble.Alarm do
  @moduledoc false

  alias Elmx.Runtime.Core.Collections.Pairs
  alias Elmx.Types

  # Mirrors `Pebble.Alarm.toPosix` in elm-watch.
  # Posix is represented as millis (same as `Time.millisToPosix` identity in elmx).
  @spec to_posix(Types.elm_value()) :: Types.maybe_like()
  def to_posix(utc_seconds) do
    seconds = Pairs.to_int(utc_seconds, nil)

    cond do
      not is_integer(seconds) -> :Nothing
      seconds < 0 -> :Nothing
      true -> {:Just, seconds * 1000}
    end
  end
end
