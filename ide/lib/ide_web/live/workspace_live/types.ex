defmodule IdeWeb.WorkspaceLive.Types do
  @moduledoc false

  alias Ide.AppStore.Listing, as: AppStoreListing
  alias Ide.AppStore.Types, as: AppStoreTypes
  alias Ide.Compiler
  alias Ide.Formatter.Types, as: FormatterTypes
  alias Ide.GitHub.Repositories
  alias Ide.GitHub.Types, as: GitHubTypes
  alias Ide.Packages.Types, as: PackageTypes
  alias Ide.PebbleToolchain
  alias Ide.PublishManifest
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.PackagesFlow
  alias IdeWeb.WorkspaceLive.PublishFlow

  @type async_exit_reason :: async_error() | atom() | tuple() | String.t()

  @type file_error :: File.posix() | atom() | String.t()

  @type async_error ::
          Compiler.compiler_error()
          | PebbleToolchain.toolchain_error()
          | PublishFlow.prepare_release_error()
          | AppStoreTypes.publish_error()
          | GitHubTypes.push_error()
          | GitHubTypes.github_error()
          | PackageTypes.package_error()
          | PublishManifest.publish_error()
          | Screenshots.screenshot_error()
          | file_error()
          | map()
          | tuple()

  @type format_tab :: map()

  @type format_success :: %{
          tab: format_tab(),
          result: FormatterTypes.format_result(),
          write_result: :ok | File.posix()
        }

  @type format_error_payload :: %{
          tab: format_tab(),
          reason: FormatterTypes.parse_error() | async_error()
        }

  @type packages_inspection :: %{
          package: String.t(),
          details: map(),
          versions: [String.t()],
          readme: String.t()
        }

  @type github_repo_created :: %{
          owner: String.t(),
          repo: String.t(),
          html_url: String.t() | nil,
          private: boolean()
        }

  @type github_push_result :: %{
          branch: String.t(),
          owner: String.t(),
          repo: String.t(),
          commit_sha: String.t(),
          remote_url: String.t(),
          committed: boolean(),
          history_replaced: boolean()
        }

  @type github_create_and_push_result :: %{
          create: github_repo_created(),
          push: github_push_result()
        }

  @type appstore_command_result :: %{
          status: :ok | :error,
          command: String.t(),
          output: String.t(),
          exit_code: integer(),
          cwd: String.t()
        }

  @type emulator_runtime_status :: map()

  @type emulator_dependency_install_result :: %{
          platform: String.t(),
          before: emulator_runtime_status(),
          after: emulator_runtime_status(),
          results: [map()],
          output: String.t()
        }

  @type async_payload ::
          {:ok, Compiler.check_result()}
          | {:error, Compiler.compiler_error()}
          | {:ok, BuildFlow.build_pipeline_result()}
          | {:ok, Compiler.compile_result()}
          | {:error, Compiler.compiler_error()}
          | {:ok, Compiler.manifest_result()}
          | {:error, Compiler.compiler_error()}
          | {{:ok, String.t()} | {:error, file_error()}, pos_integer(), String.t(), String.t()}
          | {EditorDependencies.dependency_payload(), pos_integer()}
          | {EditorDependencies.docs_payload(), pos_integer()}
          | {{:ok, Compiler.check_result()} | {:error, async_error()}, pos_integer(), String.t(),
             String.t()}
          | {:ok, format_success()}
          | {:error, format_error_payload()}
          | {:ok, PebbleToolchain.command_result()}
          | {:error, PebbleToolchain.toolchain_error()}
          | {:ok, PebbleToolchain.package_result()}
          | {:error, PebbleToolchain.toolchain_error()}
          | emulator_runtime_status()
          | {:ok, emulator_dependency_install_result()}
          | {:error, async_error()}
          | {:ok, Screenshots.capture_result()}
          | {:error, Screenshots.screenshot_error()}
          | {:ok, Screenshots.capture_all_result()}
          | {:error, Screenshots.screenshot_error()}
          | {:ok, PublishFlow.prepare_release_result()}
          | {:error, PublishFlow.prepare_release_error()}
          | AppStoreListing.result()
          | {:ok, appstore_command_result()}
          | {:error, AppStoreTypes.publish_error()}
          | github_push_result()
          | Repositories.repo_status()
          | {:error, String.t()}
          | github_repo_created()
          | {:ok, github_create_and_push_result()}
          | {:error, {:create, async_error()} | {:push, async_error()}}
          | {{:ok, PackageTypes.search_result()} | {:error, PackageTypes.package_error()},
             reference()}
          | {:ok, packages_inspection()}
          | {:error, String.t(), PackageTypes.package_error()}
          | {:ok, PublishManifest.export_result()}
          | {:error, PublishManifest.publish_error()}
          | {:ok, PublishManifest.release_notes_result()}
          | {:error, PublishManifest.publish_error()}

  @type async_result :: {:ok, async_payload()} | {:exit, async_exit_reason()}

  @type info_message ::
          {:debugger_auto_fire_refresh, String.t()}
          | {:capture_all_progress, pos_integer(), Screenshots.progress_payload()}
          | {:packages_search_progress, reference(), PackagesFlow.search_progress()}

  @type liveview_system_message ::
          {:EXIT, pid(), async_exit_reason()}
          | {:DOWN, reference(), :process | :port, pid() | port(), async_exit_reason()}
          | reference()
end
