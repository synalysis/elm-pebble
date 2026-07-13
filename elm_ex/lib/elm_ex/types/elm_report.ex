defmodule ElmEx.Types.ElmReport do
  @moduledoc """
  JSON error reports from the official Elm compiler (`elm make --report=json`).

  Runtime maps use string keys. Shapes vary by `"type"`; unknown fields are allowed.
  """

  @type region_point :: %{
          optional(atom()) => integer() | String.t() | nil,
          optional(String.t()) => integer() | String.t() | nil
        }

  @type problem_field_value ::
          String.t()
          | [problem_field_value()]
          | %{optional(atom()) => problem_field_value(), optional(String.t()) => problem_field_value()}
          | nil

  @type problem :: %{
          optional(atom()) => problem_field_value(),
          optional(String.t()) => problem_field_value()
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
          optional(atom()) => problem_field_value(),
          optional(String.t()) => problem_field_value()
        }

  @type t :: compile_errors() | compile_error() | file_errors() | problem()
end
