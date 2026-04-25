defmodule Marbles.GachaSession do
  alias Marbles.{Accounts, Catalog, Collection, Gacha, PackPullRules, Repo}
  alias Marbles.Schema.{Marble, Pack, User}

  @type pull_kind :: :one | :ten
  @type pull_kind_input :: pull_kind() | 1 | 10
  @type quote_t :: %{
          base_price: non_neg_integer(),
          final_price: non_neg_integer(),
          weight: pos_integer(),
          pull_kind: pull_kind()
        }
  @type preview_response :: %{
          pack: Pack.t(),
          quote: quote_t(),
          currency_before: non_neg_integer(),
          currency_after: non_neg_integer()
        }
  @type marble_result :: %{
          marble: Marble.t(),
          duplicate?: boolean(),
          dust: non_neg_integer()
        }
  @type execute_response :: %{
          pack: Pack.t(),
          pull_kind: pull_kind(),
          quote: quote_t(),
          currency_before: non_neg_integer(),
          currency_after: non_neg_integer(),
          marbles: [marble_result()],
          total_dust: non_neg_integer()
        }
  @type execute_opt ::
          {:source, String.t()} | {:guild_id, String.t() | nil} | {:analytics_meta, map()}

  @spec list_pullable_packs_for_web(Ecto.UUID.t() | nil) :: [map()]
  def list_pullable_packs_for_web(user_id) do
    Catalog.list_active_packs(Date.utc_today(), :newest)
    |> Enum.map(fn pack ->
      {quote_one, quote_ten, pity_line} = quotes_for_pack(pack, user_id)

      %{
        pack: pack,
        quote_one: quote_one,
        quote_ten: quote_ten,
        pity_line: pity_line
      }
    end)
  end

  @spec preview_pull_cost(Ecto.UUID.t(), Ecto.UUID.t(), pull_kind_input()) ::
          {:ok, preview_response()}
          | {:error, :invalid_pull_kind | :pack_unavailable | :user_not_found}
  def preview_pull_cost(user_id, pack_id, pull_kind_input) do
    with {:ok, pull_kind} <- normalize_pull_kind(pull_kind_input),
         {:ok, pack} <- active_pack(pack_id),
         %User{} = user <- Accounts.get_user(user_id) do
      quote = quote_for_kind(user.id, pack, pull_kind)

      {:ok,
       %{
         pack: pack,
         quote: quote,
         currency_before: user.currency,
         currency_after: max(user.currency - quote.final_price, 0)
       }}
    else
      nil -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec execute_pull(Ecto.UUID.t(), Ecto.UUID.t(), pull_kind_input(), [execute_opt()]) ::
          {:ok, execute_response()}
          | {:error, :invalid_pull_kind | :pack_unavailable | :user_not_found}
          | {:error, {:insufficient_currency, non_neg_integer(), non_neg_integer()}}
          | {:error, :pull_failed}
  def execute_pull(user_id, pack_id, pull_kind_input, opts \\ []) do
    with {:ok, pull_kind} <- normalize_pull_kind(pull_kind_input),
         {:ok, pack} <- active_pack(pack_id),
         %User{} <- Accounts.get_user(user_id) do
      source = Keyword.get(opts, :source, "web_pull")
      guild_id = Keyword.get(opts, :guild_id)
      analytics_meta = Keyword.get(opts, :analytics_meta, %{})

      case Repo.transaction(fn ->
             locked_user = lock_user!(user_id)
             quote = quote_for_kind(locked_user.id, pack, pull_kind)

             if locked_user.currency < quote.final_price do
               Repo.rollback({:insufficient_currency, quote.final_price, locked_user.currency})
             end

             marbles =
               pull_marbles!(
                 pack,
                 locked_user,
                 pull_kind,
                 guild_id,
                 source,
                 analytics_meta
               )

             if quote.final_price > 0 do
               {:ok, _} = Accounts.update_currency(locked_user, -quote.final_price)
             end

             commit_pull_rules!(locked_user.id, pack.id, pull_kind, quote)

             {marble_results, total_dust} =
               acquire_marbles(locked_user.id, pack.id, pull_kind, source, marbles)

             user_after = Repo.get!(User, locked_user.id)

             %{
               pack: pack,
               pull_kind: pull_kind,
               quote: quote,
               currency_before: locked_user.currency,
               currency_after: user_after.currency,
               marbles: marble_results,
               total_dust: total_dust
             }
           end) do
        {:ok, result} ->
          {:ok, result}

        {:error, {:insufficient_currency, _, _} = reason} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec normalize_pull_kind(pull_kind_input()) ::
          {:ok, pull_kind()} | {:error, :invalid_pull_kind}
  defp normalize_pull_kind(:one), do: {:ok, :one}
  defp normalize_pull_kind(:ten), do: {:ok, :ten}
  defp normalize_pull_kind(1), do: {:ok, :one}
  defp normalize_pull_kind(10), do: {:ok, :ten}
  defp normalize_pull_kind(_), do: {:error, :invalid_pull_kind}

  @spec active_pack(Ecto.UUID.t()) :: {:ok, Pack.t()} | {:error, :pack_unavailable}
  defp active_pack(pack_id) do
    pack =
      Catalog.list_active_packs(Date.utc_today(), :newest)
      |> Enum.find(&(&1.id == pack_id))

    case pack do
      %Pack{} = found -> {:ok, found}
      nil -> {:error, :pack_unavailable}
    end
  end

  @spec quotes_for_pack(Pack.t(), Ecto.UUID.t() | nil) :: {quote_t(), quote_t(), String.t() | nil}
  defp quotes_for_pack(pack, nil) do
    base = pack.cost || 0
    {base_quote(base, 1, :one), base_quote(base * 10, 10, :ten), nil}
  end

  defp quotes_for_pack(pack, user_id) do
    {
      PackPullRules.quote_one(user_id, pack),
      PackPullRules.quote_ten(user_id, pack),
      PackPullRules.pity_guarantee_line(pack, user_id)
    }
  end

  @spec base_quote(non_neg_integer(), pos_integer(), pull_kind()) :: quote_t()
  defp base_quote(base_price, weight, pull_kind) do
    %{
      base_price: base_price,
      final_price: base_price,
      weight: weight,
      pull_kind: pull_kind
    }
  end

  @spec quote_for_kind(Ecto.UUID.t(), Pack.t(), pull_kind()) :: quote_t()
  defp quote_for_kind(user_id, pack, :one), do: PackPullRules.quote_one(user_id, pack)
  defp quote_for_kind(user_id, pack, :ten), do: PackPullRules.quote_ten(user_id, pack)

  @spec lock_user!(Ecto.UUID.t()) :: User.t()
  defp lock_user!(user_id) do
    Repo.get!(User, user_id)
  end

  @spec pull_marbles!(Pack.t(), User.t(), pull_kind(), String.t() | nil, String.t(), map()) ::
          [Marble.t()]
  defp pull_marbles!(pack, user, pull_kind, guild_id, source, analytics_meta) do
    total_pulls = pull_count(pull_kind)

    result =
      Enum.reduce_while(1..total_pulls, [], fn _, acc ->
        min_rarity = PackPullRules.pity_force_min_rarity(user.id, pack)
        pull_opts = build_pull_opts(min_rarity, source, pull_kind, analytics_meta)

        case Gacha.pull_from_pack(pack.id, user.id, guild_id, pull_opts) do
          {:ok, marble} ->
            PackPullRules.commit_pity_after_marble!(user.id, pack.id, marble.rarity)
            {:cont, [marble | acc]}

          {:error, _} ->
            {:halt, :pull_failed}
        end
      end)

    case result do
      :pull_failed -> Repo.rollback(:pull_failed)
      marbles -> Enum.reverse(marbles)
    end
  end

  @spec build_pull_opts(non_neg_integer() | nil, String.t(), pull_kind(), map()) :: keyword()
  defp build_pull_opts(min_rarity, source, pull_kind, analytics_meta) do
    base_meta =
      analytics_meta
      |> Map.put_new("source", source)
      |> Map.put_new("pull_kind", Atom.to_string(pull_kind))

    opts = [analytics_meta: base_meta]

    if min_rarity do
      Keyword.put(opts, :min_rarity, min_rarity)
    else
      opts
    end
  end

  @spec pull_count(pull_kind()) :: 1 | 10
  defp pull_count(:one), do: 1
  defp pull_count(:ten), do: 10

  @spec commit_pull_rules!(Ecto.UUID.t(), Ecto.UUID.t(), pull_kind(), quote_t()) :: :ok
  defp commit_pull_rules!(user_id, pack_id, :one, quote) do
    PackPullRules.commit_after_one_pull!(user_id, pack_id, quote)
    :ok
  end

  defp commit_pull_rules!(user_id, pack_id, :ten, quote) do
    PackPullRules.commit_after_ten_pull!(user_id, pack_id, quote)
    :ok
  end

  @spec acquire_marbles(Ecto.UUID.t(), Ecto.UUID.t(), pull_kind(), String.t(), [Marble.t()]) ::
          {[marble_result()], non_neg_integer()}
  defp acquire_marbles(user_id, pack_id, pull_kind, source, marbles) do
    Enum.map_reduce(marbles, 0, fn marble, dust_total ->
      meta = %{
        "source" => source,
        "pack_id" => pack_id,
        "pull_kind" => Atom.to_string(pull_kind)
      }

      case Collection.acquire_marble_template(user_id, marble.id, meta: meta) do
        {:new, _user_marble} ->
          {%{marble: marble, duplicate?: false, dust: 0}, dust_total}

        {:duplicate, dust, _user_marble} ->
          {%{marble: marble, duplicate?: true, dust: dust}, dust_total + dust}
      end
    end)
  end
end
