defmodule Ide.Projects.Types do
  @moduledoc """
  Shared types for persisted project JSON fields and API boundaries.
  """

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects.FileTypes

  @type wire_input :: DebuggerTypes.wire_input()

  @type scope_user :: nil | :current_scope | %{optional(:id) => integer() | nil}

  @type github_visibility :: String.t()

  @type github_config :: %{
          optional(String.t()) => String.t()
        }

  @type github_import_repo :: %{
          required(:owner) => String.t(),
          required(:repo) => String.t(),
          required(:branch) => String.t()
        }

  @type github_clone_params :: %{
          optional(:owner) => String.t(),
          optional(:repo) => String.t(),
          optional(:branch) => String.t(),
          optional(:repo_url) => String.t(),
          optional(String.t()) => String.t()
        }

  @type release_defaults :: %{
          optional(:is_published) => boolean(),
          optional(String.t()) => String.t() | [String.t()] | boolean() | nil
        }

  @type release_defaults_carrier :: %{
          optional(:release_defaults) => release_defaults(),
          optional(:slug) => String.t(),
          optional(atom()) => term()
        }

  @type package_metadata :: %{
          optional(String.t()) => String.t() | [String.t()] | boolean() | nil
        }

  @type store_metadata :: %{
          optional(String.t()) => wire_input()
        }

  @type subscription_row :: %{
          optional(String.t()) => String.t() | integer() | boolean() | nil,
          optional(atom()) => String.t() | integer() | boolean() | nil
        }

  @type debugger_settings :: %{
          optional(:platform_target) => String.t(),
          optional(:timeline_limit) => pos_integer() | integer(),
          optional(:auto_fire) => boolean() | DebuggerTypes.wire_map(),
          optional(:watch_profile_id) => String.t(),
          optional(:geolocation) => DebuggerTypes.wire_map(),
          optional(:companion_bridge) => DebuggerTypes.wire_map(),
          optional(:auto_fire_subscriptions) => [subscription_row()],
          optional(:disabled_subscriptions) => [subscription_row()],
          optional(String.t()) => wire_input() | [subscription_row()] | DebuggerTypes.wire_map(),
          optional(atom()) => wire_input() | [subscription_row()] | DebuggerTypes.wire_map()
        }

  @type source_tree :: FileTypes.source_tree()
  @type read_result :: FileTypes.read_result()
  @type write_result :: FileTypes.write_result()

  @type project_attrs :: %{
          optional(String.t()) => String.t() | [String.t()] | boolean() | release_defaults() | github_config() | nil
        }
  @type project_error :: atom() | String.t() | tuple() | Ecto.Changeset.t()

  @type create_result :: {:ok, Ide.Projects.Project.t()} | {:error, project_error()}
  @type update_result :: {:ok, Ide.Projects.Project.t()} | {:error, project_error()}
end
