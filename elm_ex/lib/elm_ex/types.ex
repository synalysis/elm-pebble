defmodule ElmEx.Types do
  @moduledoc """
  Shared types used across elm_ex packages.
  """

  alias ElmEx.Types.ElmReport

  @type module_exposing :: nil | String.t() | [String.t()]

  @type package_versions :: %{String.t() => String.t()}

  @type dependency_sections :: %{
          optional(String.t()) => package_versions() | map()
        }

  @type detail_value :: atom() | boolean() | number() | String.t() | nil

  @type parse_reason :: atom() | {:illegal, String.t() | [char() | integer()]} | map() | tuple()

  @type elm_message_part ::
          String.t()
          | %{optional(atom()) => String.t() | boolean()}
          | [elm_message_part()]

  @type elm_report :: ElmReport.t() | [ElmReport.t()]

  @type parse_error_reason ::
          atom()
          | {integer(), module(), [term()]}
          | String.t()
          | tuple()

  @type json_field :: String.t() | integer() | boolean() | list() | map() | nil

  @typedoc "Decoded `elm.json` project metadata (string keys)."
  @type elm_json :: %{optional(String.t()) => json_field()}
end
