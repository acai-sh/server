defmodule Acai.Repo do
  use Ecto.Repo,
    otp_app: :acai,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Runs the given function inside a transaction.

  This is the project convention for multi-step atomic operations.
  If the function returns {:ok, value}, the transaction is committed and {:ok, value} is returned.
  If the function returns {:error, reason}, the transaction is rolled back and {:error, reason} is returned.

  See push.TX.1
  """
  def run_transaction(fun) when is_function(fun, 0) do
    transaction(fn ->
      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> rollback(reason)
        result -> result
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      result -> {:ok, result}
    end
  end
end
