defmodule ElmEx.IR.Types.DeadCode do
  @moduledoc """
  Types for `ElmEx.IR.DeadCode` reachability over lowered IR functions.
  """

  alias ElmEx.IR.Types.Expr

  @type function_key :: String.t()

  @type function_entry :: {String.t(), String.t(), Expr.t() | map()}

  @type function_map :: %{function_key() => function_entry()}
end
