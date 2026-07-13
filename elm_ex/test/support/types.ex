defmodule ElmEx.TestSupport.Types do
  @moduledoc false

  @type corpus_scorecard :: %{
          optional(String.t()) => String.t() | integer() | boolean() | float() | nil,
          optional(atom()) => String.t() | integer() | boolean() | float() | nil
        }
end
