defmodule Acai.Repo do
  use Ecto.Repo,
    otp_app: :acai,
    adapter: Ecto.Adapters.Postgres
end
