defmodule IdeWeb.WorkspaceLive.BuildPage.Assigns do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type flow_status :: SocketAssigns.flow_status()
  @type build_issue :: BuildFlow.build_issue()
  @type t :: SocketAssigns.t()
end
