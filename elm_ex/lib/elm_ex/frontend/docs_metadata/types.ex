defmodule ElmEx.Frontend.DocsMetadata.Types do
  @moduledoc """
  Types for `ElmEx.Frontend.DocsMetadata` parse state.
  """

  @type declaration :: %{
          required(:kind) => :alias | :union | :value,
          required(:name) => String.t(),
          required(:comment) => String.t(),
          optional(:args) => [String.t()],
          optional(:type) => String.t(),
          optional(:cases) => [[String.t() | [String.t()]]],
          optional(:line) => pos_integer()
        }

  @type parse_state :: %{
          required(:i) => non_neg_integer(),
          required(:pending_doc) => String.t() | nil,
          required(:module_comment) => String.t() | nil,
          required(:seen_declaration) => boolean(),
          required(:declarations) => %{optional(String.t()) => declaration()}
        }

  @type tokenize_error :: %{
          required(:kind) => :tokenize_error,
          required(:reason) => term(),
          required(:line) => term()
        }

  @type parse_error :: tokenize_error() | %{optional(atom()) => term(), optional(String.t()) => term()}
end
