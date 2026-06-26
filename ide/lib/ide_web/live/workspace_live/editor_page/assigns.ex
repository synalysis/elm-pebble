defmodule IdeWeb.WorkspaceLive.EditorPage.Assigns do
  @moduledoc false

  alias Ide.Compiler
  alias IdeWeb.WorkspaceLive.EditorSupport.Types, as: EditorTypes
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type pane ::
          :editor
          | :build
          | :debugger
          | :emulator
          | :publish
          | :settings
          | :resources
          | :packages
          | atom()

  @type flow_status :: SocketAssigns.flow_status()
  @type tab :: EditorTypes.tab()
  @type diagnostic :: Compiler.diagnostic() | EditorTypes.diagnostic()
  @type t :: SocketAssigns.t()
end
