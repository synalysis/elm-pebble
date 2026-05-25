defmodule ElmEx.Frontend.AstContract.Types.Pattern do
  @moduledoc """
  Parser case-expression patterns validated by `AstContract.validate_pattern/1`.
  """

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes

  @type wildcard :: %{required(:kind) => :wildcard}
  @type var_pattern :: %{required(:kind) => :var, required(:name) => String.t()}
  @type unknown :: %{required(:kind) => :unknown, required(:source) => String.t()}
  @type tuple_pattern :: %{required(:kind) => :tuple, required(:elements) => [t()]}
  @type constructor_pattern :: %{
          required(:kind) => :constructor,
          required(:name) => String.t(),
          optional(:bind) => String.t(),
          optional(:arg_pattern) => t()
        }
  @type int_pattern :: %{required(:kind) => :int, required(:value) => integer()}
  @type string_pattern :: %{required(:kind) => :string, required(:value) => String.t()}
  @type record_pattern :: %{
          required(:kind) => :record,
          required(:fields) => [String.t()],
          optional(:bind) => String.t()
        }

  @type t ::
          wildcard()
          | var_pattern()
          | unknown()
          | tuple_pattern()
          | constructor_pattern()
          | int_pattern()
          | string_pattern()
          | record_pattern()
          | %{required(:kind) => atom(), optional(atom()) => AstTypes.invalid_input()}
end
