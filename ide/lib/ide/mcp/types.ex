defmodule Ide.Mcp.Types do
  @moduledoc false

  @type stdio_read_error ::
          :missing_content_length
          | :unexpected_eof
          | Jason.DecodeError.t()
          | atom()
end
