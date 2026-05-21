defmodule ElmEx.Types do
  @moduledoc """
  Shared types used across elm_ex packages.
  """

  @type module_exposing :: nil | String.t() | [String.t()]

  @type package_versions :: %{String.t() => String.t()}

  @type dependency_sections :: %{
          optional(String.t()) => package_versions() | map()
        }

  @type detail_value :: atom() | boolean() | number() | String.t() | nil

  @type parse_reason :: atom() | {:illegal, String.t() | [char() | integer()]} | term()

  @type elm_message_part ::
          String.t()
          | %{optional(atom()) => String.t() | boolean()}
          | [elm_message_part()]

  @type elm_report :: map() | list()

  @type parse_error_reason ::
          atom()
          | {integer(), module(), [term()]}
          | String.t()
          | tuple()
end
