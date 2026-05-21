defmodule Ide.Repo do
  @moduledoc """
  Delegates to the runtime-selected repo (`Ide.Repo.Postgres` or `Ide.Repo.Sqlite`).
  """

  @delegated_functions Ide.Repo.Sqlite.__info__(:functions) -- [
                        {:__info__, 1},
                        {:module_info, 0},
                        {:module_info, 1}
                      ]

  for {name, arity} <- @delegated_functions do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)) do
      apply(repo_module(), unquote(name), [unquote_splicing(args)])
    end
  end

  @spec repo_module() :: module()
  defp repo_module do
    Application.fetch_env!(:ide, :repo_module)
  end
end
