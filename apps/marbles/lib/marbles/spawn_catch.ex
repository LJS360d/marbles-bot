defmodule Marbles.SpawnCatch do
  @moduledoc false

  alias Marbles.Repo
  alias Marbles.Schema.{CaughtSpawn, Marble}
  alias Marbles.Analytics
  alias Marbles.{Accounts, Collection}
  alias Marbles.Economy.{SpawnRewards, Upgrades}

  @spec collect(String.t(), Ecto.UUID.t(), Marble.t(), float()) ::
          {:ok,
           %{
             coins: non_neg_integer(),
             dust: non_neg_integer(),
             template: term()
           }}
          | {:error, :already_claimed}
  def collect(message_id, user_id, %Marble{} = marble, spawn_rate)
      when is_binary(message_id) and is_binary(user_id) do
    spawn_rate = spawn_rate * 1.0

    case Repo.transaction(fn ->
           case Repo.get(CaughtSpawn, message_id) do
             %CaughtSpawn{} ->
               Repo.rollback(:already_claimed)

             nil ->
               cs =
                 %CaughtSpawn{}
                 |> CaughtSpawn.changeset(%{message_id: message_id, user_id: user_id})

               case Repo.insert(cs) do
                 {:ok, _} ->
                   :ok

                 {:error, _} ->
                   Repo.rollback(:already_claimed)
               end
           end

           user = Accounts.get_user!(user_id)
           luck = Upgrades.spawn_luck_bonus(user_id)

           %{coins: coins, dust: dust} =
             SpawnRewards.roll_claim_resources(spawn_rate, marble.rarity || 1, luck)

           if coins > 0 do
             {:ok, _} = Accounts.update_currency(user, coins)
           end

           if dust > 0 do
             {:ok, _} = Accounts.update_dust(user, dust)
           end

           template =
             Collection.acquire_marble_template(user_id, marble.id, meta: %{source: "spawn"})

           %{coins: coins, dust: dust, template: template}
         end) do
      {:ok, m} ->
        template_kind =
          case m.template do
            {:new, _} -> "new"
            {:duplicate, _, _} -> "duplicate"
            _ -> "unknown"
          end

        _ =
          Analytics.record_event("spawn_claim", nil, nil, user_id, %{
            "message_id" => message_id,
            "marble_id" => marble.id,
            "spawn_rate" => spawn_rate,
            "coins" => m.coins,
            "dust" => m.dust,
            "template_kind" => template_kind
          })

        {:ok, m}

      {:error, :already_claimed} ->
        {:error, :already_claimed}

      {:error, _} ->
        {:error, :already_claimed}
    end
  end
end
