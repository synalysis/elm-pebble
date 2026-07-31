defmodule ElmEx.IR.Types.Lookup do
  @moduledoc """
  Name-resolution context threaded through `ElmEx.IR.Lowerer` rewrites and
  `ElmEx.IR.ImportResolution`.
  """


  @type payload_kind :: :none | :single | :multi | :function_like

  @type name_map :: %{String.t() => String.t()}
  @type alias_member_map :: %{String.t() => %{String.t() => String.t()}}
  @type unqualified_target :: String.t() | :ambiguous
  @type import_unqualified_map :: %{String.t() => unqualified_target()}

  @type import_resolution_t :: %{
          optional(:alias_map) => map(),
          optional(:alias_member_map) => map(),
          optional(:import_unqualified_map) => map(),
          optional(:local_call_names) => map() | MapSet.t(term()),
          optional(:current_module) => term(),
          optional(:type_unqualified_map) => map()
        }

  @type tag_map :: %{String.t() => integer()}
  @type arity_map :: %{String.t() => non_neg_integer()}
  @type kind_map :: %{String.t() => atom()}

  @type constructor_t :: %{
          required(:local) => tag_map(),
          required(:unqualified) => tag_map(),
          required(:qualified) => tag_map(),
          optional(:alias_map) => name_map()
        }

  @type payload_kind_t :: %{
          required(:local) => kind_map(),
          required(:unqualified) => kind_map(),
          required(:qualified) => kind_map(),
          optional(:alias_map) => name_map()
        }

  # Value types are intentionally wide (`map()` / `term()`): Dialyzer widens
  # MapSet and nested tag maps through map updates, and success typing must
  # remain a subtype of this contract.
  @type rewrite_t :: %{
          optional(:local) => map(),
          optional(:unqualified) => map(),
          optional(:qualified) => map(),
          optional(:payload_arity_local) => map(),
          optional(:payload_arity_unqualified) => map(),
          optional(:payload_arity_qualified) => map(),
          optional(:current_module) => term(),
          optional(:alias_map) => map(),
          optional(:alias_member_map) => map(),
          optional(:import_unqualified_map) => map(),
          optional(:type_unqualified_map) => map(),
          optional(:wildcard_import_modules) => list(),
          optional(:local_call_names) => map() | MapSet.t(term()),
          optional(:let_bound_names) => map() | MapSet.t(term()),
          optional(:record_alias_fields_local) => map(),
          optional(:record_alias_fields_unqualified) => map(),
          optional(:record_alias_fields_qualified) => map()
        }

  @type t :: rewrite_t() | constructor_t() | payload_kind_t() | import_resolution_t()

  @type import_resolution_bundle :: {
          name_map(),
          alias_member_map(),
          import_unqualified_map(),
          [String.t()],
          name_map()
        }
end
