defmodule Marbles.Accounts do
  alias Marbles.Inventory
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserIdentity, UserInventory, UserRaceStat}
  import Ecto.Query

  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id) |> Repo.preload(:identities) |> with_wallet()

  def get_user(id) when is_integer(id) do
    case Repo.get(User, id) do
      nil -> nil
      u -> Repo.preload(u, :identities) |> with_wallet()
    end
  end

  def get_user(id) when is_binary(id) and id != "" do
    case Integer.parse(id) do
      {int, ""} ->
        case Repo.get(User, int) do
          nil -> nil
          u -> Repo.preload(u, :identities) |> with_wallet()
        end

      _ ->
        case Repo.get(User, id) do
          nil -> nil
          u -> Repo.preload(u, :identities) |> with_wallet()
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
      %UserIdentity{user: user} -> with_wallet(user)
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

          :ok = Inventory.ensure_default_currency_entries(user.id)

          user
        end)
        |> case do
          {:ok, user} -> {:ok, Repo.preload(user, :identities) |> with_wallet()}
          {:error, _} = err -> err
        end

      %UserIdentity{user: user} ->
        {:ok, Repo.preload(user, :identities) |> with_wallet()}
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

    base = from(u in User, as: :u)
    base = apply_user_search(base, q)
    total = Repo.aggregate(base, :count, :id)

    ordered =
      from(u in base,
        left_join: w in subquery(wallet_subquery()),
        on: w.user_id == u.id,
        preload: :identities
      )
      |> apply_user_order(sort, order)

    users = ordered |> offset(^offset) |> limit(^per) |> Repo.all()
    {with_wallet_many(users), total}
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
    term = "%" <> (q |> admin_search_fragment() |> String.downcase()) <> "%"

    from(u in query,
      where:
        fragment("LOWER(?) LIKE ?", u.display_name, ^term) or
          exists(
            from(i in UserIdentity,
              where:
                i.user_id == parent_as(:u).id and
                  fragment("LOWER(?) LIKE ?", i.username, ^term)
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

  defp apply_user_order(query, :inserted_at, :asc),
    do: order_by(query, [u, _w], asc: u.inserted_at)

  defp apply_user_order(query, :inserted_at, :desc),
    do: order_by(query, [u, _w], desc: u.inserted_at)

  defp apply_user_order(query, :display_name, :asc),
    do: order_by(query, [u, _w], asc_nulls_last: u.display_name)

  defp apply_user_order(query, :display_name, :desc),
    do: order_by(query, [u, _w], desc_nulls_last: u.display_name)

  defp apply_user_order(query, :currency, :asc),
    do: order_by(query, [_u, w], asc: coalesce(w.coins, 0))

  defp apply_user_order(query, :currency, :desc),
    do: order_by(query, [_u, w], desc: coalesce(w.coins, 0))

  defp apply_user_order(query, :dust, :asc),
    do: order_by(query, [_u, w], asc: coalesce(w.dust, 0))

  defp apply_user_order(query, :dust, :desc),
    do: order_by(query, [_u, w], desc: coalesce(w.dust, 0))

  defp apply_user_order(query, :role, :asc), do: order_by(query, [u, _w], asc: u.role)
  defp apply_user_order(query, :role, :desc), do: order_by(query, [u, _w], desc: u.role)

  def primary_display_name(%User{} = user) do
    if user.display_name && user.display_name != "" do
      user.display_name
    else
      case List.first(identities_list(user)) do
        %{username: u} when is_binary(u) -> u
        _ -> "User"
      end
    end
  end

  def identity_username(%User{} = user, platform) do
    user = Repo.preload(user, :identities) |> with_wallet()
    identities = identities_list(user)

    case Enum.find(identities, &(&1.platform == platform)) do
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

  @spec currency_balance(Ecto.UUID.t()) :: non_neg_integer()
  def currency_balance(user_id) when is_binary(user_id) do
    Inventory.get_currency_balance(user_id, :coins)
  end

  @spec dust_balance(Ecto.UUID.t()) :: non_neg_integer()
  def dust_balance(user_id) when is_binary(user_id) do
    Inventory.get_currency_balance(user_id, :dust)
  end

  @spec wallet(Ecto.UUID.t()) :: %{coins: non_neg_integer(), dust: non_neg_integer()}
  def wallet(user_id) when is_binary(user_id) do
    :ok = Inventory.ensure_default_currency_entries(user_id)
    Inventory.get_currency_balances(user_id)
  end

  @spec set_wallet_balances(Ecto.UUID.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, %{coins: non_neg_integer(), dust: non_neg_integer()}}
          | {:error, :insufficient_quantity | :invalid_quantity}
  def set_wallet_balances(user_id, coins, dust)
      when is_binary(user_id) and is_integer(coins) and coins >= 0 and is_integer(dust) and
             dust >= 0 do
    :ok = Inventory.ensure_default_currency_entries(user_id)
    {coins_type, coins_id} = Inventory.currency_item_key(:coins)
    {dust_type, dust_id} = Inventory.currency_item_key(:dust)

    Repo.transaction(fn ->
      case Inventory.set_item_quantity(user_id, coins_type, coins_id, coins, %{
             "source" => "owner_admin"
           }) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      case Inventory.set_item_quantity(user_id, dust_type, dust_id, dust, %{
             "source" => "owner_admin"
           }) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      wallet(user_id)
    end)
    |> case do
      {:ok, balances} -> {:ok, balances}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_currency(User.t(), integer()) ::
          {:ok, User.t()} | {:error, :insufficient_currency | :invalid_quantity}
  def update_currency(%User{} = user, amount) when is_integer(amount) do
    {item_type, item_id} = Inventory.currency_item_key(:coins)

    case Inventory.change_item_quantity(user.id, item_type, item_id, amount) do
      {:ok, _} ->
        {:ok, with_wallet(user)}

      {:error, :insufficient_quantity} ->
        {:error, :insufficient_currency}

      {:error, :invalid_quantity} ->
        {:error, :invalid_quantity}
    end
  end

  @spec update_dust(User.t(), integer()) ::
          {:ok, User.t()} | {:error, :insufficient_dust | :invalid_quantity}
  def update_dust(%User{} = user, amount) when is_integer(amount) do
    {item_type, item_id} = Inventory.currency_item_key(:dust)

    case Inventory.change_item_quantity(user.id, item_type, item_id, amount) do
      {:ok, _} ->
        {:ok, with_wallet(user)}

      {:error, :insufficient_quantity} ->
        {:error, :insufficient_dust}

      {:error, :invalid_quantity} ->
        {:error, :invalid_quantity}
    end
  end

  def set_role(user, role) when role in [:regular, :server_admin, :owner] do
    user
    |> User.changeset(%{role: role})
    |> Repo.update()
  end

  @spec wallet_subquery() :: Ecto.Query.t()
  defp wallet_subquery do
    from(ui in UserInventory,
      where: ui.item_type == ^Inventory.currency_item_type(),
      group_by: ui.user_id,
      select: %{
        user_id: ui.user_id,
        coins:
          fragment(
            "SUM(CASE WHEN ? = ? THEN ? ELSE 0 END)",
            ui.item_id,
            ^Inventory.coins_item_id(),
            ui.quantity
          ),
        dust:
          fragment(
            "SUM(CASE WHEN ? = ? THEN ? ELSE 0 END)",
            ui.item_id,
            ^Inventory.dust_item_id(),
            ui.quantity
          )
      }
    )
  end

  @spec with_wallet_many([User.t()]) :: [User.t()]
  defp with_wallet_many(users) when is_list(users) do
    balances = Inventory.currency_balances_for_users(Enum.map(users, & &1.id))

    Enum.map(users, fn user ->
      wallet = Map.get(balances, user.id, %{coins: 0, dust: 0})
      %{user | currency: wallet.coins, dust: wallet.dust}
    end)
  end

  @spec with_wallet(User.t()) :: User.t()
  defp with_wallet(%User{} = user) do
    wallet = wallet(user.id)
    %{user | currency: wallet.coins, dust: wallet.dust}
  end

  @spec identities_list(User.t()) :: [map()]
  defp identities_list(%User{identities: identities}) when is_list(identities), do: identities
  defp identities_list(_), do: []
end
