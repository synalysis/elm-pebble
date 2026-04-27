defmodule Ide.Packages.Http do
  @moduledoc false

  @type conditional :: %{optional(:etag) => String.t(), optional(:last_modified) => String.t()}
  @type response_cache :: %{
          optional(:etag) => String.t() | nil,
          optional(:last_modified) => String.t() | nil
        }

  @spec get_json(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_json(path, opts) when is_binary(path) and is_list(opts) do
    with {:ok, body} <- get_text(path, opts),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_json, error.data}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  GET JSON with optional validators for conditional requests (`If-None-Match`, `If-Modified-Since`).

  Returns `{:ok, decoded, cache_meta}` on 200, `:not_modified` on 304, or `{:error, reason}`.
  """
  @spec get_json_conditional(String.t(), keyword(), conditional()) ::
          {:ok, term(), response_cache()} | :not_modified | {:error, term()}
  def get_json_conditional(path, opts, conditional \\ %{})
      when is_binary(path) and is_list(opts) do
    case Keyword.get(opts, :download_progress) do
      progress when is_function(progress, 1) ->
        case stream_text_conditional(path, opts, conditional, progress) do
          {:ok, body, meta} ->
            progress.({:phase, :decoding_json})

            case Jason.decode(body) do
              {:ok, decoded} -> {:ok, decoded, meta}
              {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_json, error.data}}
            end

          :not_modified ->
            :not_modified

          {:error, _} = err ->
            err
        end

      _ ->
        case get_text_conditional(path, opts, conditional) do
          {:ok, body, meta} ->
            case Jason.decode(body) do
              {:ok, decoded} -> {:ok, decoded, meta}
              {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_json, error.data}}
            end

          :not_modified ->
            :not_modified

          {:error, _} = err ->
            err
        end
    end
  end

  @spec get_text(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_text(path, opts) when is_binary(path) and is_list(opts) do
    base_url = opts[:base_url] || ""
    timeout = opts[:timeout_ms] || 8_000
    accept = opts[:accept] || "application/json"

    url = base_url |> String.trim_trailing("/") |> Kernel.<>(path)

    request =
      Finch.build(:get, url, [
        {"accept", accept},
        {"accept-encoding", "gzip"},
        {"user-agent", "elm-pebble-ide/1.0"}
      ])

    case Finch.request(request, Ide.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, maybe_gunzip(body)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:network, reason}}
    end
  end

  @doc false
  @spec get_text_conditional(String.t(), keyword(), conditional()) ::
          {:ok, String.t(), response_cache()} | :not_modified | {:error, term()}
  def get_text_conditional(path, opts, conditional)
      when is_binary(path) and is_list(opts) and is_map(conditional) do
    timeout = opts[:timeout_ms] || 8_000
    request = build_conditional_request(path, opts, conditional)

    case Finch.request(request, Ide.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 304, headers: resp_headers}} ->
        _ = resp_headers
        :not_modified

      {:ok, %Finch.Response{status: status, headers: resp_headers, body: body}}
      when status in 200..299 ->
        {:ok, maybe_gunzip(body), response_cache_meta(resp_headers)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:network, reason}}
    end
  end

  @spec build_conditional_request(term(), term(), term()) :: term()
  defp build_conditional_request(path, opts, conditional) do
    base_url = opts[:base_url] || ""
    accept = opts[:accept] || "application/json"

    url = base_url |> String.trim_trailing("/") |> Kernel.<>(path)

    headers =
      [
        {"accept", accept},
        {"accept-encoding", "gzip"},
        {"user-agent", "elm-pebble-ide/1.0"}
      ]
      |> prepend_conditional_headers(conditional)

    Finch.build(:get, url, headers)
  end

  @spec stream_text_conditional(term(), term(), term(), term()) :: term()
  defp stream_text_conditional(path, opts, conditional, progress)
       when is_binary(path) and is_list(opts) and is_map(conditional) and is_function(progress, 1) do
    receive_timeout = Keyword.get(opts, :receive_timeout_ms, 120_000)
    request_timeout = Keyword.get(opts, :index_timeout_ms, 240_000)
    request = build_conditional_request(path, opts, conditional)

    progress.({:phase, :connecting})

    stream_opts = [
      receive_timeout: receive_timeout,
      request_timeout: request_timeout
    ]

    acc0 = %{
      status: nil,
      header_blocks: [],
      chunks: [],
      content_length: nil,
      last_progress_bytes: 0,
      last_progress_at: 0,
      announced_download: false
    }

    case Finch.stream_while(
           request,
           Ide.Finch,
           acc0,
           &stream_conditional_chunk(progress, &1, &2),
           stream_opts
         ) do
      {:ok, %{status: 304}} ->
        :not_modified

      {:ok, %{status: status, header_blocks: blocks, chunks: chunks}} when status in 200..299 ->
        flat_headers = blocks |> Enum.reverse() |> Enum.concat()
        meta = response_cache_meta(flat_headers)
        raw = chunks |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, maybe_gunzip(raw), meta}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status, ""}}

      {:error, exception, _acc} ->
        {:error, {:network, exception}}
    end
  end

  @spec stream_conditional_chunk(term(), term(), term()) :: term()
  defp stream_conditional_chunk(_progress, {:status, status}, acc) do
    {:cont, %{acc | status: status}}
  end

  defp stream_conditional_chunk(_progress, {:headers, headers}, acc) do
    blocks = [headers | acc.header_blocks]
    flat = Enum.concat(Enum.reverse(blocks))
    cl = content_length_from_header_list(flat)

    {:cont, %{acc | header_blocks: blocks, content_length: cl || acc.content_length}}
  end

  defp stream_conditional_chunk(progress, {:data, chunk}, acc) when is_binary(chunk) do
    acc = Map.update!(acc, :chunks, &[chunk | &1])
    received = acc.chunks |> Enum.reduce(0, fn c, n -> n + byte_size(c) end)

    acc =
      if acc.status in 200..299 && !acc.announced_download do
        cl = acc.content_length

        if is_integer(cl) && cl > 0 do
          progress.({:phase, {:download_started, cl}})
        else
          progress.({:phase, :download_started})
        end

        %{acc | announced_download: true}
      else
        acc
      end

    acc = throttle_download_progress(progress, acc, received)
    {:cont, acc}
  end

  defp stream_conditional_chunk(_progress, {:trailers, _}, acc), do: {:cont, acc}

  @spec throttle_download_progress(term(), term(), term()) :: term()
  defp throttle_download_progress(progress, acc, received) do
    now = System.monotonic_time(:millisecond)
    total = acc.content_length
    delta_b = received - acc.last_progress_bytes
    delta_t = now - acc.last_progress_at

    heavy? = delta_b >= 524_288
    timed? = delta_t >= 400
    done? = is_integer(total) && received >= total

    if heavy? or timed? or done? do
      progress.({:bytes, received, total})
      %{acc | last_progress_bytes: received, last_progress_at: now}
    else
      acc
    end
  end

  @spec content_length_from_header_list(term()) :: term()
  defp content_length_from_header_list(headers) when is_list(headers) do
    case Enum.find_value(headers, fn {k, v} ->
           if String.downcase(to_string(k)) == "content-length" do
             Integer.parse(to_string(v))
           end
         end) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  @spec prepend_conditional_headers(term(), term()) :: term()
  defp prepend_conditional_headers(headers, conditional) do
    headers
    |> prepend_if(conditional[:etag], fn e -> {"if-none-match", e} end)
    |> prepend_if(conditional[:last_modified], fn lm -> {"if-modified-since", lm} end)
  end

  @spec prepend_if(term(), term(), term()) :: term()
  defp prepend_if(headers, value, pair_fun) do
    if is_binary(value) and String.trim(value) != "" do
      [pair_fun.(value) | headers]
    else
      headers
    end
  end

  @spec response_cache_meta(term()) :: term()
  defp response_cache_meta(headers) when is_list(headers) do
    norm =
      Enum.reduce(headers, %{}, fn {k, v}, acc ->
        Map.put(acc, String.downcase(to_string(k)), to_string(v))
      end)

    %{etag: Map.get(norm, "etag"), last_modified: Map.get(norm, "last-modified")}
  end

  @spec maybe_gunzip(term()) :: term()
  defp maybe_gunzip(body) when is_binary(body) do
    if byte_size(body) >= 2 and match?(<<0x1F, 0x8B, _::binary>>, body) do
      try do
        :zlib.gunzip(body)
      rescue
        _ -> body
      end
    else
      body
    end
  end
end
