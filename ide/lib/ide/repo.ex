defmodule Ide.Repo do
  use Ecto.Repo,
    otp_app: :ide,
    adapter: Ecto.Adapters.SQLite3
end
