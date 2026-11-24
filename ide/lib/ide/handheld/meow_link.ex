defmodule Ide.Handheld.MeowLink do
  @moduledoc false

  @timeout_ms 60_000

  @spec install(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def install(package_dir, opts \\ []) when is_binary(package_dir) do
    with {:ok, port} <- port(opts),
         {:ok, id, manifest, blob} <- package(package_dir),
         :ok <- talk(port, request(id, manifest, blob), "MEOW launch #{id}\n") do
      {:ok, "Installed #{id} on the MeowKit and started it."}
    else
      {:error, :not_connected} ->
        {:error,
         "MeowKit is not connected over USB. Plug it in and leave USB Mass Storage turned off."}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "MeowKit install failed: #{inspect(reason)}"}
    end
  end

  @spec request(String.t(), binary(), binary()) :: binary()
  def request(id, manifest, blob) when is_binary(id) and is_binary(manifest) and is_binary(blob) do
    "MEOW install #{id} #{byte_size(manifest)} #{byte_size(blob)}\n" <> manifest <> blob
  end

  @spec accept(String.t()) :: :ok | {:error, String.t()}
  def accept(line) when is_binary(line) do
    case String.trim(line) do
      "MEOW ok" -> :ok
    "MEOW go" -> :go
      "MEOW err " <> reason -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp package(dir) do
    manifest_path = Path.join(dir, "manifest.json")
    blob_path = Path.join(dir, "app.meow")

    with {:ok, manifest} <- File.read(manifest_path),
         {:ok, blob} <- File.read(blob_path),
         {:ok, id} <- app_id(manifest) do
      {:ok, id, manifest, blob}
    else
      {:error, :bad_id} -> {:error, "The MeowKit package has no app id."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp app_id(manifest) do
    case Regex.run(~r/"id"\s*:\s*"([A-Za-z0-9_-]{1,32})"/, manifest) do
      [_, id] -> {:ok, id}
      _ -> {:error, :bad_id}
    end
  end

  defp port(opts) do
    case Keyword.get(opts, :port) do
      port when is_binary(port) and port != "" ->
        if File.exists?(port), do: {:ok, port}, else: {:error, :not_connected}

      _ ->
        case Path.wildcard("/dev/serial/by-id/*Espressif*if02") do
          [found | _] -> {:ok, found}
          [] -> {:error, :not_connected}
        end
    end
  end

  defp talk(port, payload, launch) do
    prepare(port)

    {header, body} = split_header(payload)

    File.open(port, [:binary, :read, :write, :raw], fn io ->
      IO.binwrite(io, header)

      with :go <- read_status(io),
           :ok <- write_paced(io, body),
           :ok <- read_status(io),
           :ok <- IO.binwrite(io, launch),
           :ok <- read_status(io) do
        :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_header(payload) do
    [header, body] = String.split(payload, "\n", parts: 2)
    {header <> "\n", body}
  end

  defp write_paced(_io, <<>>), do: :ok

  defp write_paced(io, data) do
    size = min(256, byte_size(data))
    IO.binwrite(io, binary_part(data, 0, size))

    case read_ack(io, System.monotonic_time(:millisecond) + @timeout_ms) do
      :ok -> write_paced(io, binary_part(data, size, byte_size(data) - size))
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_ack(io, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, "The MeowKit stopped accepting the app."}
    else
      case IO.binread(io, 1) do
        "." -> :ok
        :eof ->
          Process.sleep(10)
          read_ack(io, deadline)

        {:error, reason} ->
          {:error, reason}

        _ ->
          read_ack(io, deadline)
      end
    end
  end

  defp prepare(port) do
    System.cmd("stty", [
      "-F",
      port,
      "115200",
      "raw",
      "-echo",
      "-ixon",
      "cs8",
      "-cstopb",
      "-parenb",
      "min",
      "0",
      "time",
      "20"
    ])
  end

  defp read_status(io) do
    read_status(io, System.monotonic_time(:millisecond) + @timeout_ms)
  end

  defp read_status(io, deadline) do
    case read_line(io, deadline, []) do
      {:ok, line} ->
        case accept(line) do
          :ok ->
            :ok

          :go ->
            :go

          {:error, _} = error ->
            if String.starts_with?(String.trim(line), "MEOW"),
              do: error,
              else: read_status(io, deadline)
        end

      other ->
        other
    end
  end

  defp read_line(io, deadline, acc) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, "The MeowKit did not answer."}
    else
      case IO.binread(io, 1) do
        "\n" ->
          {:ok, IO.iodata_to_binary(Enum.reverse(acc))}

        "\r" ->
          read_line(io, deadline, acc)

        <<byte>> ->
          read_line(io, deadline, [byte | acc])

        :eof ->
          Process.sleep(20)
          read_line(io, deadline, acc)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
