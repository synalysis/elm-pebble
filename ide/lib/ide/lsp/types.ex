defmodule Ide.Lsp.Types do
  @moduledoc false

  alias Ide.Tokenizer.Types, as: TokenizerTypes

  @type wire_value :: String.t() | boolean() | integer() | [String.t()] | wire_map() | nil

  @type wire_map :: %{optional(String.t()) => wire_value()}

  @type document :: %{
          required(:text) => String.t(),
          required(:version) => integer() | nil,
          required(:tokens) => [TokenizerTypes.token()],
          required(:parser_payload) => TokenizerTypes.parser_payload(),
          required(:diagnostics) => [TokenizerTypes.diagnostic()]
        }

  @type wire_message :: %{optional(String.t()) => wire_value()}

  @type server_info :: %{
          optional(String.t()) => String.t()
        }

  @type capabilities :: %{
          optional(String.t()) => wire_value()
        }

  @type initialize_result :: %{
          optional(String.t()) => capabilities() | server_info() | wire_value()
        }
end
