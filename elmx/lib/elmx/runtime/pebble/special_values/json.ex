defmodule Elmx.Runtime.Pebble.SpecialValues.Json do
  @moduledoc false

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "Json.Encode.string" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_string", args: args}}

      "Json.Encode.int" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_int", args: args}}

      "Json.Encode.bool" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_bool", args: args}}

      "Json.Encode.array" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_array", args: args}}

      "Json.Encode.set" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_set", args: args}}

      "Json.Encode.dict" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_dict", args: args}}

      "Json.Encode.object" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_object", args: args}}

      "Json.Encode.list" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_list", args: args}}

      "Json.Encode.null" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_null", args: []}}

      "Json.Encode.float" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_float", args: args}}

      "Json.Encode.encode" ->
        {:ok, %{op: :runtime_call, function: "elmx_json_encode_encode", args: args}}

      _ ->
        :unmatched
    end
  end
end
