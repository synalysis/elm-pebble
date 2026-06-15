defmodule Elmc.CLI.Types do
  @moduledoc """
  Typed results returned by in-process `Elmc.CLI` project runners.
  """

  @type cli_diagnostic :: %{
          optional(:severity) => String.t(),
          optional(:message) => String.t(),
          optional(:source) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:line) => integer() | nil,
          optional(:column) => integer() | nil,
          optional(:warning_type) => atom() | String.t() | nil,
          optional(:warning_code) => atom() | String.t() | nil,
          optional(:warning_constructor) => String.t() | nil,
          optional(:warning_expected_kind) => atom() | String.t() | nil,
          optional(:warning_has_arg_pattern) => boolean() | nil,
          optional(String.t()) => String.t() | integer() | boolean() | nil
        }

  @type run_status :: :ok | :error

  @type project_run :: %{
          required(:status) => run_status(),
          required(:output) => String.t(),
          required(:warnings) => [cli_diagnostic()]
        }

  @type manifest_run :: %{
          required(:status) => run_status(),
          required(:output) => String.t(),
          required(:warnings) => [cli_diagnostic()],
          required(:manifest) => map() | nil
        }
end
