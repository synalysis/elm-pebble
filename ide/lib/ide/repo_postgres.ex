defmodule Ide.Repo.Postgres do
  use Ecto.Repo,
    otp_app: :ide,
    adapter: Ecto.Adapters.Postgres
end
