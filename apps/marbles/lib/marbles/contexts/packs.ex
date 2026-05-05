defmodule Marbles.Packs do
  alias Marbles.Repo
  alias Marbles.Schema.{Pack, Marble, PackPullRule}
  alias Marbles.{Catalog, PackPullRules}
  import Ecto.Query

  @spec broadcast_commands_resync() :: :ok
  def broadcast_commands_resync do
    Phoenix.PubSub.broadcast(Marbles.PubSub, "commands_resync", :resync)
  end

  @spec create_pack(map()) :: {:ok, Pack.t()} | {:error, Ecto.Changeset.t()}
  def create_pack(attrs \\ %{}) do
    %Pack{}
    |> Pack.changeset(attrs)
    |> Repo.insert()
    |> broadcast_on_success()
  end

  @spec update_pack(Pack.t(), map()) :: {:ok, Pack.t()} | {:error, Ecto.Changeset.t()}
  def update_pack(%Pack{} = pack, attrs) do
    pack
    |> Pack.changeset(attrs)
    |> Repo.update()
    |> broadcast_on_success()
  end

  @spec delete_pack(Pack.t()) :: {:ok, Pack.t()} | {:error, Ecto.Changeset.t()}
  def delete_pack(%Pack{} = pack) do
    pack
    |> Repo.delete()
    |> broadcast_on_success()
  end

  @spec broadcast_on_success({:ok, Pack.t()} | {:error, Ecto.Changeset.t()}) ::
          {:ok, Pack.t()} | {:error, Ecto.Changeset.t()}
  defp broadcast_on_success({:ok, _} = result) do
    _ = broadcast_commands_resync()
    result
  end

  defp broadcast_on_success({:error, _} = err), do: err

  @spec get_pack!(Ecto.UUID.t()) :: Pack.t()
  def get_pack!(id), do: Repo.get!(Pack, id) |> Repo.preload([:marbles, :pull_rules])

  @spec list_active_packs(Date.t()) :: [Pack.t()]
  def list_active_packs(as_of \\ Date.utc_today()), do: Catalog.list_active_packs(as_of)

  @spec list_all_packs(keyword()) :: [Pack.t()]
  def list_all_packs(opts \\ []), do: Catalog.list_all_packs(opts)

  @spec list_packs(keyword()) :: {[Pack.t()], non_neg_integer()}
  def list_packs(opts \\ []), do: Catalog.list_packs(opts)

  @spec set_pack_marbles(Pack.t(), [Ecto.UUID.t()]) ::
          {:ok, Pack.t()} | {:error, Ecto.Changeset.t()}
  def set_pack_marbles(%Pack{} = pack, marble_ids) when is_list(marble_ids) do
    marbles = Repo.all(from(m in Marble, where: m.id in ^marble_ids))
    pack = Repo.preload(pack, :marbles)

    pack
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:marbles, marbles)
    |> Repo.update()
  end

  @spec save_pack_complete(Pack.t() | nil, map(), [Ecto.UUID.t()], [map()]) ::
          {:ok, Pack.t()} | {:error, Ecto.Changeset.t()} | {:error, {:rules, String.t()}}
  def save_pack_complete(maybe_pack, pack_params, marble_ids, rule_rows)
      when is_list(marble_ids) and is_list(rule_rows) do
    rule_rows =
      Enum.filter(rule_rows, fn r ->
        t = r[:trigger_type] || r["trigger_type"]
        e = r[:effect_type] || r["effect_type"]
        is_binary(t) and t != "" and is_binary(e) and e != ""
      end)

    case PackPullRules.validate_rule_rows(rule_rows) do
      {:error, msg} ->
        {:error, {:rules, msg}}

      :ok ->
        result =
          Repo.transaction(fn ->
            pack =
              case maybe_pack do
                nil ->
                  %Pack{}
                  |> Pack.changeset(pack_params)
                  |> Repo.insert!()

                %Pack{} = p ->
                  p
                  |> Pack.changeset(pack_params)
                  |> Repo.update!()
              end

            Repo.delete_all(from(o in PackPullRule, where: o.pack_id == ^pack.id))

            Enum.each(rule_rows, fn row ->
              attrs = PackPullRules.row_attrs(pack.id, row)

              %PackPullRule{}
              |> PackPullRule.changeset(attrs)
              |> Repo.insert!()
            end)

            case set_pack_marbles(pack, marble_ids) do
              {:ok, p} -> p
              {:error, cs} -> Repo.rollback(cs)
            end
          end)

        case result do
          {:ok, pack} ->
            broadcast_commands_resync()
            {:ok, pack}

          {:error, _} = err ->
            err
        end
    end
  end
end
