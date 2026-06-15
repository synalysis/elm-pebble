defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns.Match do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Patterns.Match.{Bindings, Pattern}
  alias Elmx.Types

  @type env :: Types.emit_env()

  defdelegate branch_env(branch, env), to: Bindings
  defdelegate branch_pattern_root(branch), to: Bindings
  defdelegate branch_pattern(branch, env \\ %{}), to: Pattern
end
