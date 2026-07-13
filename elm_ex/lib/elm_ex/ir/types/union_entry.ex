defmodule ElmEx.IR.Types.UnionEntry do
  @moduledoc """
  Union metadata attached to `ElmEx.IR.Module.unions` after lowering.
  """

  alias ElmEx.CoreIR.Types
  alias ElmEx.Frontend.AstContract.Types.UnionConstructor

  @type payload_kinds :: %{optional(String.t()) => atom() | String.t()}

  @type constructor_wire :: UnionConstructor.t() | %{optional(atom() | String.t()) => String.t() | nil}

  @type t :: %{
          optional(:constructors) => [constructor_wire()],
          optional(:tags) => %{String.t() => pos_integer()},
          optional(:payload_specs) => %{String.t() => String.t() | nil},
          optional(:payload_kinds) => payload_kinds(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_union_entry :: %{
          optional(:constructors) => [constructor_wire()],
          optional(:tags) => %{optional(String.t()) => pos_integer()},
          optional(:payload_specs) => %{optional(String.t()) => String.t() | nil},
          optional(:payload_kinds) => payload_kinds(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }
end
