defmodule Marbles.Packs do
  alias Marbles.Repo
  alias Marbles.Schema.Pack
  alias Marbles.Catalog

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

  def get_pack!(id), do: Repo.get!(Pack, id) |> Repo.preload(:marbles)
  def list_active_packs(as_of \\ Date.utc_today()), do: Catalog.list_active_packs(as_of)
end
