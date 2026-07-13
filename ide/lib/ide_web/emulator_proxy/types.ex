defmodule IdeWeb.EmulatorProxy.Types do
  @moduledoc false

  @type ws_connect_info :: WebSockex.Conn.t()

  @type tcp_error_reason :: :econnrefused | :etimedout | :nxdomain | :closed | atom()

  @type ws_start_error :: :already_started | atom()

  @type ws_close_reason :: atom() | String.t()

  @type stop_reason ::
          :normal
          | {:tcp_connect_failed, tcp_error_reason()}
          | {:ws_connect_failed, ws_start_error()}
          | {:tcp_send_failed, atom()}

  @type ws_terminate_reason ::
          {:error, ws_close_reason()}
          | {:local, :normal | pos_integer()}
          | {:remote, :closed | :normal | pos_integer()}
          | {:local, pos_integer(), binary()}
          | {:remote, pos_integer(), binary()}
          | stop_reason()
          | :killed
          | {:shutdown, ws_close_reason()}

  @type terminate_reason :: ws_terminate_reason()

  @type proxy_info_message ::
          {:tcp, port(), binary()}
          | {:tcp_closed, port()}
          | {:tcp_error, port(), atom()}
          | {:emulator_proxy_frame, {:binary, binary()} | {:text, binary()}}
          | {:emulator_proxy_closed, terminate_reason()}
          | :emulator_proxy_upstream_connected
end
