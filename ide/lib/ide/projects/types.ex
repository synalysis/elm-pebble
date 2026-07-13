defmodule Ide.Projects.Types do
  @moduledoc """
  Shared types for persisted project JSON fields and API boundaries.
  """

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.GitHub.Types, as: GitHubTypes
  alias Ide.ProjectBundle
  alias Ide.ProjectImport
  alias Ide.Projects.BootstrapError
  alias Ide.Projects.FileTypes
  alias Ide.Resources.Types, as: ResourceTypes

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
          optional(:name) => String.t(),
          optional(:store_app_id) => String.t() | nil,
          optional(:app_uuid) => String.t() | nil,
          optional(:github) => github_config()
        }

  @type package_metadata :: %{
          optional(String.t()) => String.t() | [String.t()] | boolean() | nil
        }

  @type store_metadata :: %{
          optional(String.t()) => wire_input()
        }

  @type subscription_row :: %{
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(String.t()) => String.t() | integer() | boolean() | nil
        }

  @type auto_fire_targets :: %{
          optional(:watch) => boolean(),
          optional(:companion) => boolean(),
          optional(:phone) => boolean(),
          optional(String.t()) => boolean()
        }

  @type debugger_settings :: %{
          optional(:platform_target) => String.t(),
          optional(:timeline_limit) => pos_integer() | integer(),
          optional(:timeline_mode) => String.t(),
          optional(:watch_profile_id) => String.t(),
          optional(:emulator_target) => String.t(),
          optional(:emulator_mode) => String.t(),
          optional(:configuration_values) => DebuggerTypes.CompanionConfiguration.values(),
          optional(:auto_fire) => auto_fire_targets(),
          optional(:auto_fire_subscriptions) => [subscription_row()],
          optional(:disabled_subscriptions) => [subscription_row()],
          optional(:simulator) => DebuggerTypes.simulator_settings(),
          optional(String.t()) =>
            wire_input()
            | [subscription_row()]
            | auto_fire_targets()
            | DebuggerTypes.simulator_settings()
        }

  @type source_tree :: FileTypes.source_tree()
  @type read_result :: FileTypes.read_result()
  @type write_result :: FileTypes.write_result()

  @type project_attrs :: %{
          optional(String.t()) => String.t() | [String.t()] | boolean() | release_defaults() | github_config() | nil
        }
  @type project_error ::
          BootstrapError.bootstrap_reason()
          | Ecto.Changeset.t()
          | atom()
          | String.t()
          | File.posix()
          | ProjectImport.import_error()
          | ProjectBundle.bundle_error()
          | ProjectBundle.import_source_error()
          | GitHubTypes.clone_error()
          | ResourceTypes.resource_error()

  @type create_result :: {:ok, Ide.Projects.Project.t()} | {:error, project_error()}
  @type update_result :: {:ok, Ide.Projects.Project.t()} | {:error, project_error()}
end
