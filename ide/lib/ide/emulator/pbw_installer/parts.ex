defmodule Ide.Emulator.PBWInstaller.Parts do
  @moduledoc false

  require Logger

  alias Ide.Emulator.PBW
  alias Ide.Emulator.PBWInstaller.{PostInstall, Putbytes}
  alias Ide.Emulator.Types
  alias Ide.Emulator.PebbleProtocol.CRC32
  alias Ide.Emulator.PebbleProtocol.Packets

  @spec send_parts(
          pid(),
          [PBW.part()],
          non_neg_integer(),
          pos_integer(),
          timeout(),
          timeout(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          timeout(),
          non_neg_integer()
        ) :: {:ok, [Types.install_part_sent()]} | {:error, Types.install_error()}
  def send_parts(
        router,
        parts,
        app_id,
        chunk_size,
        timeout,
        install_timeout,
        part_delay_ms,
        putbytes_retries,
        chunk_delay_ms,
        install_transition_timeout,
        part_retries
      ) do
    install_parts = sort_parts_for_install(parts)

    install_parts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {part, index}, {:ok, sent_parts} ->
      maybe_delay_between_parts(index, part_delay_ms)
      final_part? = index == length(install_parts) - 1

      case send_part(
             router,
             part,
             app_id,
             chunk_size,
             timeout,
             install_timeout,
             putbytes_retries,
             chunk_delay_ms,
             install_transition_timeout,
             part_retries,
             final_part?
           ) do
        {:ok, sent_part} -> {:cont, {:ok, [sent_part | sent_parts]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sent_parts} -> {:ok, Enum.reverse(sent_parts)}
      error -> error
    end
  end

  @doc false
  @spec sort_parts_for_install([PBW.part()]) :: [PBW.part()]
  def sort_parts_for_install(parts), do: Enum.sort_by(parts, &install_part_order/1)

  defp install_part_order(%{kind: :binary}), do: 0
  defp install_part_order(%{kind: :resources}), do: 1
  defp install_part_order(%{kind: :worker}), do: 2
  defp install_part_order(_part), do: 3

  defp send_part(
         router,
         part,
         app_id,
         chunk_size,
         timeout,
         install_timeout,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         retries_left,
         install_part?
       ) do
    case send_part_once(
           router,
           part,
           app_id,
           chunk_size,
           timeout,
           install_timeout,
           putbytes_retries,
           chunk_delay_ms,
           install_transition_timeout,
           install_part?
         ) do
      {:error, {:putbytes_failed, %{phase: :commit, cookie: cookie} = meta, {:nack, _}}}
      when retries_left > 0 ->
        Logger.debug(
          "native pbw install commit NACK kind=#{part.kind} cookie=#{cookie}; resending part"
        )

        _ =
          Putbytes.send_putbytes(
            router,
            Packets.putbytes_abort(cookie),
            nil,
            Map.merge(meta, %{phase: :abort_after_commit_nack}),
            timeout,
            putbytes_retries
          )

        Process.sleep(100)

        send_part(
          router,
          part,
          app_id,
          chunk_size,
          timeout,
          install_timeout,
          putbytes_retries,
          chunk_delay_ms,
          install_transition_timeout,
          retries_left - 1,
          install_part?
        )

      result ->
        result
    end
  end

  defp send_part_once(
         router,
         part,
         app_id,
         chunk_size,
         timeout,
         install_timeout,
         putbytes_retries,
         chunk_delay_ms,
         install_transition_timeout,
         install_part?
       ) do
    object_type = Packets.object_type(part.object_type)
    {init_endpoint, init_payload} = Packets.putbytes_app_init(part.size, object_type, app_id)

    Logger.debug(
      "native pbw install part init kind=#{part.kind} size=#{part.size} app_id=#{app_id}"
    )

    with {:ok, init} <-
           Putbytes.send_putbytes(
             router,
             {init_endpoint, init_payload},
             nil,
             %{phase: :init, kind: part.kind, size: part.size, app_id: app_id},
             timeout,
             putbytes_retries
           ),
         cookie <- init.cookie,
         _ <- Logger.debug("native pbw install part cookie kind=#{part.kind} cookie=#{cookie}"),
         {:ok, bytes_sent} <-
           Putbytes.send_chunks(
             router,
             part.kind,
             part.data,
             cookie,
             chunk_size,
             timeout,
             putbytes_retries,
             chunk_delay_ms
           ),
         crc <- CRC32.stm32(part.data),
         _ <-
           Logger.debug(
             "native pbw install part commit kind=#{part.kind} bytes=#{bytes_sent} crc=#{crc}"
           ),
         {:ok, _commit} <-
           Putbytes.send_putbytes(
             router,
             Packets.putbytes_commit(cookie, crc),
             nil,
             %{phase: :commit, kind: part.kind, cookie: cookie, bytes_sent: bytes_sent, crc: crc},
             timeout,
             putbytes_retries
           ),
         :ok <-
           maybe_install_part(
             router,
             part.kind,
             cookie,
             install_timeout,
             putbytes_retries,
             install_transition_timeout,
             install_part?
           ) do
      {:ok,
       %{
         kind: part.kind,
         name: part.name,
         cookie: cookie,
         bytes: bytes_sent,
         crc: crc
       }}
    end
  end

  defp maybe_install_part(
         router,
         kind,
         cookie,
         install_timeout,
         putbytes_retries,
         _install_transition_timeout,
         true
       ) do
    Logger.debug("native pbw install part install kind=#{kind} cookie=#{cookie}")
    expected_cookies = [cookie, 0]

    with {:ok, _} <-
           Putbytes.send_putbytes(
             router,
             Packets.putbytes_install(cookie),
             expected_cookies,
             %{phase: :install, kind: kind, cookie: cookie},
             install_timeout,
             putbytes_retries
           ) do
      PostInstall.observe_post_install_frame(router, kind)
    end
  end

  defp maybe_install_part(
         router,
         kind,
         cookie,
         _install_timeout,
         _putbytes_retries,
         install_transition_timeout,
         false
       ) do
    Logger.debug("native pbw install transition part install kind=#{kind} cookie=#{cookie}")

    case Putbytes.send_putbytes(
           router,
           Packets.putbytes_install(cookie),
           nil,
           %{phase: :install_transition, kind: kind, cookie: cookie},
           install_transition_timeout,
           0
         ) do
      {:ok, _install} ->
        :ok

      {:error, {:putbytes_failed, %{phase: :install_transition}, :timeout}} ->
        Logger.debug(
          "native pbw install transition timed out kind=#{kind} cookie=#{cookie}; continuing"
        )

        :ok

      {:error, {:putbytes_failed, %{phase: :install_transition}, {:timeout, observed}}} ->
        Logger.debug(
          "native pbw install transition timed out kind=#{kind} cookie=#{cookie} observed=#{inspect(observed)}; continuing"
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_delay_between_parts(0, _delay_ms), do: :ok
  defp maybe_delay_between_parts(_index, delay_ms) when delay_ms <= 0, do: :ok

  defp maybe_delay_between_parts(_index, delay_ms) do
    Logger.debug("native pbw install waiting #{delay_ms}ms before next part")
    Process.sleep(delay_ms)
  end
end
