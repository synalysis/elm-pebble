defmodule Elmx.Runtime.Intrinsics.Registry.Singleton do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_append" => {Core, :append},
      "elmc_new_char" => {Core, :new_char}
    }
  end
end
