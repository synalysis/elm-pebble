defmodule ElmEx.Typesys.Layout do
  @moduledoc """
  Derive storage / plan produce tags from elaborated `Type.t()`.
  """

  alias ElmEx.Typesys.Type

  @type produce_kind :: :native_int | :native_bool | :owned

  @spec produce_kind(Type.t() | nil) :: produce_kind()
  def produce_kind(type) do
    case Type.primitive_kind(type) do
      :int -> :native_int
      :bool -> :native_bool
      _ -> :owned
    end
  end
end
