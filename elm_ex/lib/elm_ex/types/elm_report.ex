defmodule ElmEx.Types.ElmReport do
  @moduledoc """
  JSON error reports from the official Elm compiler (`elm make --report=json`).

  Runtime maps use string keys. Shapes vary by `"type"`; unknown fields are allowed.
  """

  @type region_point :: %{
          optional(atom()) => integer() | String.t() | nil,
          optional(String.t()) => integer() | String.t() | nil
        }

  @type problem :: %{
          optional(atom()) => String.t() | [term()] | map() | nil,
          optional(String.t()) => String.t() | [term()] | map() | nil
        }

  @typedoc "Per-file error bundle inside `\"type\": \"compile-errors\"` reports."
  @type file_errors :: %{
          optional(atom()) => String.t() | [problem()],
          optional(String.t()) => String.t() | [problem()]
        }

  @typedoc "Top-level `compile-errors` report."
  @type compile_errors :: %{
          optional(atom()) => String.t() | [file_errors()],
          optional(String.t()) => String.t() | [file_errors()]
        }

  @typedoc "Single-title `error` report."
  @type compile_error :: %{
          optional(atom()) => String.t() | [term()],
          optional(String.t()) => String.t() | [term()]
        }

  @type t :: compile_errors() | compile_error() | file_errors() | problem()
end
