defmodule ElmEx.IR.Types.UnionEntry do
  @moduledoc """
  Union metadata attached to `ElmEx.IR.Module.unions` after lowering.
  """

  alias ElmEx.Frontend.AstContract.Types.UnionConstructor

  @type payload_kinds :: %{optional(String.t()) => atom() | String.t()}

  @type t :: %{
          optional(:constructors) => [UnionConstructor.t() | map()],
          optional(:tags) => %{String.t() => pos_integer()},
          optional(:payload_specs) => %{String.t() => String.t() | nil},
          optional(:payload_kinds) => payload_kinds(),
          optional(atom()) => term()
        }
end
