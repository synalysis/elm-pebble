defmodule Elmx.Runtime.Pebble.Registry.Http do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Http

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    for fun <- ~w(get post request expect_string expect_json header string_body json_body empty_body)a,
        into: %{} do
      {"elmx_http_#{fun}", {Http, fun}}
    end
  end
end
