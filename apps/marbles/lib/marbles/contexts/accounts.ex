defmodule Marbles.Accounts do
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserIdentity}
  import Ecto.Query

  def get_user!(id), do: Repo.get!(User, id) |> Repo.preload(:identities)

  def get_user_by_platform(platform_id, platform \\ "discord") do
    from(i in UserIdentity,
      where: i.platform_id == ^platform_id and i.platform == ^platform,
      join: u in User,
      on: u.id == i.user_id,
      preload: [user: u]
    )
    |> Repo.one()
    |> case do
      %UserIdentity{user: user} -> user
      nil -> nil
    end
  end

  def get_identity_by_platform(platform_id, platform \\ "discord") do
    Repo.get_by(UserIdentity, platform_id: platform_id, platform: platform)
    |> Repo.preload(:user)
  end

  def ensure_user(attrs) do
    case get_identity_by_platform(attrs.platform_id, attrs.platform) do
      nil ->
        role = if attrs.platform_id in owner_platform_ids(), do: :owner, else: :regular
        user_attrs = %{display_name: attrs.display_name, role: role}
        identity_attrs = %{
          platform: attrs.platform,
          platform_id: attrs.platform_id,
          username: attrs.username
        }

        Repo.transaction(fn ->
          {:ok, user} =
            %User{}
            |> User.changeset(user_attrs)
            |> Repo.insert()

          %UserIdentity{}
          |> UserIdentity.changeset(Map.merge(identity_attrs, %{user_id: user.id}))
          |> Repo.insert!()

          user
        end)
        |> case do
          {:ok, user} -> {:ok, Repo.preload(user, :identities)}
          {:error, _} = err -> err
        end

      %UserIdentity{user: user} ->
        {:ok, Repo.preload(user, :identities)}
    end
  end

  defp owner_platform_ids do
    Application.get_env(:marbles, :owner_platform_ids, [])
  end

  def list_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per = Keyword.get(opts, :per_page, 20)
    offset = (max(1, page) - 1) * per
    base = from(u in User, order_by: [desc: u.inserted_at], preload: :identities)
    total = Repo.aggregate(base, :count, :id)
    users = base |> offset(^offset) |> limit(^per) |> Repo.all()
    {users, total}
  end

  def primary_display_name(%User{} = user) do
    if user.display_name && user.display_name != "" do
      user.display_name
    else
      case List.first(user.identities || []) do
        %{username: u} when is_binary(u) -> u
        _ -> "User"
      end
    end
  end

  def identity_username(%User{} = user, platform) do
    user = Repo.preload(user, :identities)
    case Enum.find(user.identities || [], &(&1.platform == platform)) do
      %{username: u} -> u
      _ -> primary_display_name(user)
    end
  end

  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def update_currency(user, amount) do
    user
    |> User.changeset(%{currency: user.currency + amount})
    |> Repo.update()
  end

  def set_role(user, role) when role in [:regular, :server_admin, :owner] do
    user
    |> User.changeset(%{role: role})
    |> Repo.update()
  end

  def can_free_pull?(user) do
    today = Date.utc_today()
    is_nil(user.last_free_pull_at) or Date.compare(user.last_free_pull_at, today) == :lt
  end

  def set_last_free_pull_at(user) do
    user
    |> User.changeset(%{last_free_pull_at: Date.utc_today()})
    |> Repo.update()
  end
end
