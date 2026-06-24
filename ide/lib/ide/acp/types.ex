defmodule Ide.Acp.Types do
  @moduledoc false

  alias Ide.Mcp.WireTypes

  @type mcp_server_env :: %{optional(String.t()) => String.t()}

  @type mcp_server_stdio :: %{
          optional(String.t()) => String.t() | [String.t()] | mcp_server_env()
        }

  @typedoc """
  JSON-RPC wire objects exchanged over ACP stdio (requests, responses, notifications).
  """
  @type wire_message :: %{optional(String.t()) => WireTypes.json_value()}

  @type json_rpc_params :: wire_message() | [WireTypes.json_value()] | nil

  @type json_rpc_result :: wire_message() | [WireTypes.json_value()] | nil

  @type acp_error :: String.t() | wire_message() | atom() | tuple()

  @type prompt_content_block :: %{
          optional(:type) => String.t(),
          optional(:text) => String.t(),
          optional(String.t()) => WireTypes.json_value()
        }
end
