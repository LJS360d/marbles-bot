defmodule Marbles.Packs do
  alias Marbles.Repo
  alias Marbles.Schema.{Pack, Marble, PackPullRule}
  alias Marbles.{Catalog, PackPullRules}
  import Ecto.Query

  def broadcast_commands_resync do
    Phoenix.PubSub.broadcast(Marbles.PubSub, "commands_resync", :resync)
  end

  def create_pack(attrs \\ %{}) do
    case %Pack{}
         |> Pack.changeset(attrs)
         |> Repo.insert() do
      {:ok, _pack} = result ->
        broadcast_commands_resync()
        result

      error ->
        error
    end
  end

  def update_pack(%Pack{} = pack, attrs) do
    case pack
         |> Pack.changeset(attrs)
         |> Repo.update() do
      {:ok, _} = result ->
        broadcast_commands_resync()
        result

      error ->
        error
    end
  end

  def delete_pack(%Pack{} = pack) do
    case Repo.delete(pack) do
      {:ok, _} = result ->
        broadcast_commands_resync()
        result

      error ->
        error
    end
  end

  def get_pack!(id), do: Repo.get!(Pack, id) |> Repo.preload([:marbles, :pull_rules])
  def list_active_packs(as_of \\ Date.utc_today()), do: Catalog.list_active_packs(as_of)
  def list_all_packs(opts \\ []), do: Catalog.list_all_packs(opts)
  def list_packs(opts \\ []), do: Catalog.list_packs(opts)

  def set_pack_marbles(%Pack{} = pack, marble_ids) when is_list(marble_ids) do
    marbles = Repo.all(from(m in Marble, where: m.id in ^marble_ids))
    pack = Repo.preload(pack, :marbles)

    pack
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:marbles, marbles)
    |> Repo.update()
  end

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
