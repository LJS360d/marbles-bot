defmodule Marbles.Accounts do
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserIdentity, UserRaceStat}
  import Ecto.Query

  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id) |> Repo.preload(:identities)

  def get_user(id) when is_integer(id) do
    case Repo.get(User, id) do
      nil -> nil
      u -> Repo.preload(u, :identities)
    end
  end

  def get_user(id) when is_binary(id) and id != "" do
    case Integer.parse(id) do
      {int, ""} ->
        case Repo.get(User, int) do
          nil -> nil
          u -> Repo.preload(u, :identities)
        end

      _ ->
        case Repo.get(User, id) do
          nil -> nil
          u -> Repo.preload(u, :identities)
        end
    end
  end

  def get_user(_), do: nil

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
        user_attrs = %{display_name: Map.get(attrs, :display_name, attrs.username), role: role}

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

  @user_sort ~w(inserted_at display_name currency dust role)a

  @spec list_users(keyword()) :: {[User.t()], non_neg_integer()}
  def list_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1) |> max(1)
    per = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per
    sort = normalize_user_sort(Keyword.get(opts, :sort))
    order = normalize_user_order(Keyword.get(opts, :order))
    q = Keyword.get(opts, :q, "") |> to_string() |> String.trim()

    base = from(u in User, as: :u, preload: :identities)
    base = apply_user_search(base, q)
    total = Repo.aggregate(base, :count, :id)
    ordered = apply_user_order(base, sort, order)
    users = ordered |> offset(^offset) |> limit(^per) |> Repo.all()
    {users, total}
  end

  defp normalize_user_sort(nil), do: :inserted_at

  defp normalize_user_sort(s) when is_atom(s) do
    if s in @user_sort, do: s, else: :inserted_at
  end

  defp normalize_user_sort(s) when is_binary(s) do
    case s do
      "inserted_at" -> :inserted_at
      "display_name" -> :display_name
      "currency" -> :currency
      "dust" -> :dust
      "role" -> :role
      _ -> :inserted_at
    end
  end

  defp normalize_user_order(:asc), do: :asc
  defp normalize_user_order("asc"), do: :asc
  defp normalize_user_order(_), do: :desc

  defp apply_user_search(query, ""), do: query

  defp apply_user_search(query, q) do
    term = "%" <> admin_search_fragment(q) <> "%"

    from(u in query,
      where:
        ilike(u.display_name, ^term) or
          exists(
            from(i in UserIdentity,
              where: i.user_id == parent_as(:u).id and ilike(i.username, ^term)
            )
          )
    )
  end

  defp admin_search_fragment(q) do
    q
    |> String.replace("\\", "")
    |> String.replace("%", "")
    |> String.replace("_", "")
  end

  defp apply_user_order(query, :inserted_at, :asc), do: order_by(query, [u], asc: u.inserted_at)
  defp apply_user_order(query, :inserted_at, :desc), do: order_by(query, [u], desc: u.inserted_at)

  defp apply_user_order(query, :display_name, :asc),
    do: order_by(query, [u], asc_nulls_last: u.display_name)

  defp apply_user_order(query, :display_name, :desc),
    do: order_by(query, [u], desc_nulls_last: u.display_name)

  defp apply_user_order(query, :currency, :asc), do: order_by(query, [u], asc: u.currency)
  defp apply_user_order(query, :currency, :desc), do: order_by(query, [u], desc: u.currency)
  defp apply_user_order(query, :dust, :asc), do: order_by(query, [u], asc: u.dust)
  defp apply_user_order(query, :dust, :desc), do: order_by(query, [u], desc: u.dust)
  defp apply_user_order(query, :role, :asc), do: order_by(query, [u], asc: u.role)
  defp apply_user_order(query, :role, :desc), do: order_by(query, [u], desc: u.role)

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

  @spec get_or_create_user_race_stat(Ecto.UUID.t()) :: UserRaceStat.t()
  def get_or_create_user_race_stat(user_id) when is_binary(user_id) do
    case Repo.get_by(UserRaceStat, user_id: user_id) do
      %UserRaceStat{} = stat ->
        stat

      nil ->
        %UserRaceStat{}
        |> UserRaceStat.changeset(%{user_id: user_id})
        |> Repo.insert!()
    end
  end

  @spec update_user_race_stat(Ecto.UUID.t(), map()) ::
          {:ok, UserRaceStat.t()} | {:error, Ecto.Changeset.t()}
  def update_user_race_stat(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    user_id
    |> get_or_create_user_race_stat()
    |> UserRaceStat.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.update()
  end

  def update_currency(user, amount) do
    user
    |> User.changeset(%{currency: user.currency + amount})
    |> Repo.update()
  end

  @spec update_dust(Marbles.Schema.User.t(), integer()) ::
          {:ok, Marbles.Schema.User.t()} | {:error, Ecto.Changeset.t()}
  def update_dust(user, amount) do
    user
    |> User.changeset(%{dust: user.dust + amount})
    |> Repo.update()
  end

  def set_role(user, role) when role in [:regular, :server_admin, :owner] do
    user
    |> User.changeset(%{role: role})
    |> Repo.update()
  end
end
