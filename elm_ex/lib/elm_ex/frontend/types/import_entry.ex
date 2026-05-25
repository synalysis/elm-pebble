defmodule ElmEx.Frontend.Types.ImportEntry do
  @moduledoc """
  Parsed `import` line metadata from `GeneratedParser`.
  """

  # `".."` open exposing is represented as the binary `".."` at runtime.
  @type exposing :: nil | String.t() | [String.t()]

  @type t :: %{
          required(:module) => String.t(),
          optional(:as) => String.t() | nil,
          optional(:exposing) => exposing(),
          optional(String.t()) => String.t() | integer() | boolean() | list() | nil
        }

  @type wire_map :: t() | map()
end
