# User operations
defmodule Marbles.Accounts do
  alias Marbles.Repo
  alias Marbles.Schema.User

  def get_user_by_platform(platform_id, platform \\ "discord") do
    Repo.get_by(User, platform_id: platform_id, platform: platform)
  end

  def ensure_user(attrs) do
    case get_user_by_platform(attrs.platform_id, attrs.platform) do
      nil ->
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def update_currency(user, amount) do
    user
    |> User.changeset(%{currency: user.currency + amount})
    |> Repo.update()
  end
end
