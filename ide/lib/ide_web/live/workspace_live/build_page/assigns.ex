defmodule IdeWeb.WorkspaceLive.BuildPage.Assigns do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.BuildFlow

  @type flow_status :: :idle | :running | :ok | :error | atom()
  @type build_issue :: BuildFlow.build_issue()

  @type t :: %{
          optional(:pane) => atom(),
          optional(:build_status) => flow_status(),
          optional(:build_output) => String.t() | nil,
          optional(:build_issues) => [build_issue()],
          optional(:manifest_strict_mode) => boolean(),
          optional(:check_status) => flow_status(),
          optional(:check_output) => String.t() | nil,
          optional(:compile_status) => flow_status(),
          optional(:compile_output) => String.t() | nil,
          optional(:manifest_status) => flow_status(),
          optional(:manifest_output) => String.t() | nil,
          optional(atom()) => term()
        }
end
