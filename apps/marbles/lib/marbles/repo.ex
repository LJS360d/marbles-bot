defmodule Marbles.Repo do
  use Ecto.Repo,
    otp_app: :marbles,
    adapter: Ecto.Adapters.SQLite3
end
