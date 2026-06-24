defmodule ElmEx.IR.Types.TopoSort do
  @moduledoc """
  Graph types for `ElmEx.IR.TopoSort` module dependency ordering.
  """

  @type module_name :: String.t()

  @type dependency_graph :: %{module_name() => [module_name()]}

  @type in_degree_map :: %{module_name() => integer()}

  @type reverse_dependency_graph :: dependency_graph()
end
