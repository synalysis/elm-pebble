defmodule Ide.Debugger.Types.SpeakerCommand do
  @moduledoc """
  Debugger speaker effect commands from `cmd.effect.speaker` package rows.

  Runtime maps use **string keys** at the wire boundary; typespec keys are atoms
  for Dialyzer (see `wire_map/0`).
  """

  alias Ide.Debugger.Types

  @type play_tone :: %{
          optional(:variant) => String.t(),
          optional(:kind) => String.t(),
          optional(:frequency_hz) => number(),
          optional(:duration_ms) => number(),
          optional(:volume) => number(),
          optional(:waveform) => number(),
          optional(String.t()) => Types.wire_input()
        }

  @type play_notes :: %{
          optional(:variant) => String.t(),
          optional(:kind) => String.t(),
          optional(:note_values) => [number()],
          optional(:volume) => number(),
          optional(String.t()) => Types.wire_input()
        }

  @type play_tracks :: %{
          optional(:variant) => String.t(),
          optional(:kind) => String.t(),
          optional(:track_values) => [number()],
          optional(:volume) => number(),
          optional(String.t()) => Types.wire_input()
        }

  @type stop :: %{
          optional(:variant) => String.t(),
          optional(:kind) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @type unknown_variant :: Types.wire_string_map()

  @type t :: play_tone() | play_notes() | play_tracks() | stop() | unknown_variant()

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
