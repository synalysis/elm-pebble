defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ViewOutputRow do
  @moduledoc """
  Draw-pipeline rows emitted by `SemanticExecutor` (`"kind"` discriminant, string keys).
  """

  @type kind :: String.t()

  @type context_kind :: :push_context | :pop_context

  @type clear_row :: %{optional(:kind) => kind(), optional(:color) => integer()}
  @type line_row :: %{
          optional(:kind) => kind(),
          optional(:x1) => integer(),
          optional(:y1) => integer(),
          optional(:x2) => integer(),
          optional(:y2) => integer(),
          optional(:color) => integer()
        }

  @type rect_row :: %{
          optional(:kind) => kind(),
          optional(:x) => integer(),
          optional(:y) => integer(),
          optional(:w) => integer(),
          optional(:h) => integer(),
          optional(:fill) => integer(),
          optional(:radius) => integer()
        }

  @type bitmap_in_rect_row :: %{
          optional(:kind) => kind(),
          optional(:bitmap_id) => integer(),
          optional(:x) => integer(),
          optional(:y) => integer(),
          optional(:w) => integer(),
          optional(:h) => integer()
        }

  @type text_row :: %{
          optional(:kind) => kind(),
          optional(:x) => integer(),
          optional(:y) => integer(),
          optional(:w) => integer(),
          optional(:h) => integer(),
          optional(:font_id) => integer(),
          optional(:text) => String.t(),
          optional(:alignment) => integer(),
          optional(:overflow) => integer()
        }

  @type vector_at_row :: %{
          optional(:kind) => kind(),
          optional(:vector_id) => integer(),
          optional(:x) => integer(),
          optional(:y) => integer()
        }

  @type unresolved_row :: %{
          optional(:kind) => kind(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type style_row :: %{
          optional(:kind) => kind(),
          optional(:value) => term(),
          optional(:color) => integer()
        }

  @type context_row :: %{optional(:kind) => kind()}

  @type t ::
          clear_row()
          | line_row()
          | rect_row()
          | bitmap_in_rect_row()
          | text_row()
          | vector_at_row()
          | style_row()
          | context_row()
          | unresolved_row()
          | wire_row()

  @type wire_row :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type view_output :: [t()]
end
