defmodule Ide.Emulator.PebbleProtocol.Packets do
  @moduledoc false

  import Bitwise, only: [bor: 2]

  alias Ide.Emulator.PebbleProtocol.Frame

  @endpoint_app_run_state 52
  @endpoint_app_fetch 6001
  @endpoint_blob_db 0xB1DB
  @endpoint_put_bytes 0xBEEF

  @putbytes_ack 0x01
  @putbytes_nack 0x02
  @blob_success 0x01

  @object_types %{
    binary: 0x05,
    resources: 0x04,
    worker: 0x07
  }

  @spec endpoint(atom()) :: non_neg_integer()
  def endpoint(:app_run_state), do: @endpoint_app_run_state
  def endpoint(:app_fetch), do: @endpoint_app_fetch
  def endpoint(:blob_db), do: @endpoint_blob_db
  def endpoint(:put_bytes), do: @endpoint_put_bytes

  @spec object_type(atom()) :: non_neg_integer()
  def object_type(name), do: Map.fetch!(@object_types, name)

  @spec app_run_state_start(String.t()) :: {non_neg_integer(), binary()}
  def app_run_state_start(uuid), do: {@endpoint_app_run_state, <<0x01, uuid_bytes(uuid)::binary>>}

  @spec app_fetch_start_response() :: {non_neg_integer(), binary()}
  def app_fetch_start_response, do: {@endpoint_app_fetch, <<0x01, 0x01>>}

  @spec blob_insert_app(non_neg_integer(), map()) :: {non_neg_integer(), binary()}
  def blob_insert_app(token, metadata) do
    key = uuid_bytes(metadata.uuid)
    value = app_metadata(metadata)

    {@endpoint_blob_db,
     <<0x01, token::little-16, 0x02, byte_size(key), key::binary, byte_size(value)::little-16,
       value::binary>>}
  end

  @spec app_metadata(map()) :: binary()
  def app_metadata(metadata) do
    name = fixed_string(Map.fetch!(metadata, :app_name), 96)

    <<uuid_bytes(Map.fetch!(metadata, :uuid))::binary, Map.fetch!(metadata, :flags)::little-32,
      Map.fetch!(metadata, :icon_resource_id)::little-32,
      Map.fetch!(metadata, :app_version_major), Map.fetch!(metadata, :app_version_minor),
      Map.fetch!(metadata, :sdk_version_major), Map.fetch!(metadata, :sdk_version_minor), 0, 0,
      name::binary>>
  end

  @spec putbytes_app_init(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  def putbytes_app_init(size, object_type, app_id) do
    {@endpoint_put_bytes, <<0x01, size::32, bor(object_type, 0x80), app_id::32>>}
  end

  @spec putbytes_put(non_neg_integer(), binary()) :: {non_neg_integer(), binary()}
  def putbytes_put(cookie, payload) do
    {@endpoint_put_bytes, <<0x02, cookie::32, byte_size(payload)::32, payload::binary>>}
  end

  @spec putbytes_commit(non_neg_integer(), non_neg_integer()) :: {non_neg_integer(), binary()}
  def putbytes_commit(cookie, crc), do: {@endpoint_put_bytes, <<0x03, cookie::32, crc::32>>}

  @spec putbytes_abort(non_neg_integer()) :: {non_neg_integer(), binary()}
  def putbytes_abort(cookie), do: {@endpoint_put_bytes, <<0x04, cookie::32>>}

  @spec putbytes_install(non_neg_integer()) :: {non_neg_integer(), binary()}
  def putbytes_install(cookie), do: {@endpoint_put_bytes, <<0x05, cookie::32>>}

  @spec frame({non_neg_integer(), binary()}) :: binary()
  def frame({endpoint, payload}), do: Frame.encode(endpoint, payload)

  @spec decode_app_fetch_request(binary()) ::
          {:ok, %{uuid: String.t(), app_id: non_neg_integer()}} | {:error, term()}
  def decode_app_fetch_request(<<0x01, uuid::binary-size(16), app_id::little-32>>) do
    {:ok, %{uuid: format_uuid(uuid), app_id: app_id}}
  end

  def decode_app_fetch_request(payload), do: {:error, {:unexpected_app_fetch_payload, payload}}

  @spec decode_blob_response(binary()) ::
          {:ok, %{token: non_neg_integer(), response: non_neg_integer(), success?: boolean()}}
          | {:error, term()}
  def decode_blob_response(<<token::little-16, response>>) do
    {:ok, %{token: token, response: response, success?: response == @blob_success}}
  end

  def decode_blob_response(payload), do: {:error, {:unexpected_blob_response_payload, payload}}

  @spec decode_putbytes_response(binary()) ::
          {:ok, %{ack?: boolean(), result: :ack | :nack, cookie: non_neg_integer()}}
          | {:error, term()}
  def decode_putbytes_response(<<@putbytes_ack, cookie::32>>) do
    {:ok, %{ack?: true, result: :ack, cookie: cookie}}
  end

  def decode_putbytes_response(<<@putbytes_nack, cookie::32>>) do
    {:ok, %{ack?: false, result: :nack, cookie: cookie}}
  end

  def decode_putbytes_response(payload), do: {:error, {:unexpected_putbytes_payload, payload}}

  @spec putbytes_ack?(map(), non_neg_integer() | nil) :: :ok | {:error, term()}
  def putbytes_ack?(%{ack?: true, cookie: cookie}, expected_cookie)
      when is_nil(expected_cookie) or cookie == expected_cookie,
      do: :ok

  def putbytes_ack?(%{ack?: true, cookie: cookie}, expected_cookie),
    do: {:error, {:wrong_cookie, expected_cookie, cookie}}

  def putbytes_ack?(%{ack?: false, cookie: cookie}, _expected_cookie),
    do: {:error, {:nack, cookie}}

  defp uuid_bytes(uuid) when is_binary(uuid) do
    uuid
    |> String.replace("-", "")
    |> Base.decode16!(case: :mixed)
  end

  defp fixed_string(value, length) do
    value = value |> to_string() |> String.slice(0, length) |> :unicode.characters_to_binary()
    padding = length - byte_size(value)
    value <> :binary.copy(<<0>>, padding)
  end

  defp format_uuid(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
           e::binary-size(6)>>
       ) do
    [a, b, c, d, e]
    |> Enum.map(&Base.encode16(&1, case: :lower))
    |> Enum.join("-")
  end
end
