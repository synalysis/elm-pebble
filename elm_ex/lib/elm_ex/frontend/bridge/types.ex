defmodule ElmEx.Frontend.Bridge.Types do
  @moduledoc """
  Wire maps produced when adapting frontend / lowerer diagnostics for Bridge consumers.
  """

  alias ElmEx.Types

  @typedoc "Lowerer diagnostic adapted for JSON-ish Bridge project diagnostics."
  @type lowerer_diagnostic :: %{
          optional(atom()) => String.t() | integer() | boolean() | nil,
          optional(String.t()) => String.t() | integer() | boolean() | nil
        }

  @type config_error :: %{
          required(:kind) => :config_error,
          required(:reason) => atom() | term(),
          optional(:path) => String.t()
        }

  @type parse_error :: %{
          required(:kind) => :parse_error,
          required(:path) => String.t(),
          optional(:line) => integer() | String.t() | nil,
          optional(:reason) => Types.parse_reason()
        }

  @type elm_check_failed :: %{
          required(:kind) => :elm_check_failed,
          required(:diagnostics) => [Types.elm_report()],
          required(:raw) => String.t()
        }

  @type bridge_error :: config_error() | parse_error() | elm_check_failed() | map()

  @type lowerer_warning :: lowerer_diagnostic() | %{
          required(:source) => String.t(),
          optional(atom()) => Types.detail_value(),
          optional(String.t()) => Types.detail_value()
        }
end
