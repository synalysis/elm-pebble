defmodule Ide.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Ide.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Ide.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ide.DataCase
    end
  end

  setup tags do
    Ide.DataCase.setup_sandbox(tags)

    if debugger_session_exclusive?(tags) do
      timeout = tags[:ownership_timeout] || tags[:timeout] || 300_000
      :ok = Ide.TestSupport.DebuggerSessionLock.acquire(timeout)
      on_exit(fn -> Ide.TestSupport.DebuggerSessionLock.release() end)
    end

    :ok
  end

  @doc false
  def debugger_session_exclusive?(tags) do
    tags[:async] == false and
      (tags[:integration] == true or tags[:template_corpus] == true or
         tags[:template_corpus_step] == true or tags[:compiled_elixir_corpus] == true or
         tags[:debugger_session] == true)
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  @type test_tags :: %{
          optional(atom()) => boolean() | integer() | atom() | String.t() | pos_integer() | nil
        }

  @spec setup_sandbox(test_tags()) :: :ok
  def setup_sandbox(tags) do
    sandbox_opts = [
      shared: not tags[:async],
      ownership_timeout: tags[:ownership_timeout] || 300_000
    ]

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Ide.Repo.Sqlite, sandbox_opts)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  @spec errors_on(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
