defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Patterns.{Case, Match}
  alias Elmx.Types

  @type env :: Types.emit_env()
  @type compile_result :: {iodata(), env(), non_neg_integer()}

  defdelegate compile_case(expr, env, counter), to: Case
  defdelegate branch_env(branch, env), to: Match
  defdelegate branch_pattern(branch, env \\ %{}), to: Match
end
