defmodule ElmEx.IR.Types.Lookup do
  @moduledoc """
  Name-resolution context threaded through `ElmEx.IR.Lowerer` rewrites and
  `ElmEx.IR.ImportResolution`.
  """

  @type payload_kind :: :none | :single | :multi | :function_like

  @type name_map :: %{String.t() => String.t()}
  @type unqualified_target :: String.t() | :ambiguous
  @type import_unqualified_map :: %{String.t() => unqualified_target()}

  @type import_resolution_t :: %{
          optional(:alias_map) => name_map(),
          optional(:import_unqualified_map) => import_unqualified_map(),
          optional(:local_call_names) => MapSet.t(String.t()),
          optional(:current_module) => String.t(),
          optional(:type_unqualified_map) => name_map()
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

  @type rewrite_t :: %{
          optional(:local) => tag_map(),
          optional(:unqualified) => tag_map(),
          optional(:qualified) => tag_map(),
          optional(:payload_arity_local) => arity_map(),
          optional(:payload_arity_unqualified) => arity_map(),
          optional(:payload_arity_qualified) => arity_map(),
          optional(:current_module) => String.t(),
          optional(:alias_map) => name_map(),
          optional(:import_unqualified_map) => import_unqualified_map(),
          optional(:type_unqualified_map) => name_map(),
          optional(:wildcard_import_modules) => [String.t()] | list(),
          optional(:local_call_names) => MapSet.t(String.t()),
          optional(:let_bound_names) => MapSet.t(String.t())
        }

  @type t :: rewrite_t() | constructor_t() | payload_kind_t() | import_resolution_t()

  @type import_resolution_bundle :: {
          name_map(),
          import_unqualified_map(),
          [String.t()],
          name_map()
        }
end
