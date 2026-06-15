defmodule Elmx.Runtime.Pebble.Registry.Json do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_json_encode_object" => {Dispatch, :json_encode_object},
      "elmx_json_encode_string" => {Dispatch, :json_encode_string},
      "elmx_json_encode_int" => {Dispatch, :json_encode_int},
      "elmx_json_encode_bool" => {Dispatch, :json_encode_bool},
      "elmx_json_encode_list" => {Dispatch, :json_encode_list},
      "elmx_json_encode_array" => {Dispatch, :json_encode_list},
      "elmx_json_encode_set" => {Dispatch, :json_encode_list},
      "elmx_json_encode_dict" => {Dispatch, :json_encode_dict},
      "elmx_json_encode_null" => {Dispatch, :json_encode_null},
      "elmx_json_encode_float" => {Dispatch, :json_encode_float},
      "elmx_json_encode_encode" => {Dispatch, :json_encode_encode}
    }
  end
end
