defmodule Marbles.Racing.Events do
  @moduledoc """
  Scheduled-event orchestration.

  An event is owner-defined (see `Marbles.Schema.Event`). Players sign up
  with a chosen squad during the signup window, paying an entry fee. When
  `start_time` is reached, `Marbles.Racing.Events.Runner` divides
  registrations into pools, runs each pool race, and computes payouts.
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Economy.Wallet
  alias Marbles.Racing.Squads
  alias Marbles.Racing.Events.{Config, Eligibility, Runner}
  alias Marbles.Schema.{Event, EventRegistration, InboxMessage}

  @type registration_error ::
          :event_not_found
          | :event_closed
          | :already_registered
          | :insufficient_funds
          | :ineligible
          | :invalid_squad

  @spec list_upcoming(non_neg_integer()) :: [Event.t()]
  def list_upcoming(limit \\ 20) do
    now = DateTime.utc_now()

    from(e in Event,
      where: e.active == true and e.end_time > ^now,
      order_by: [asc: e.start_time],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec list_for_admin(non_neg_integer(), non_neg_integer()) :: [Event.t()]
  def list_for_admin(limit \\ 50, offset \\ 0) do
    from(e in Event,
      order_by: [desc: e.start_time],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @spec get_event(Ecto.UUID.t()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> {:error, :not_found}
      e -> {:ok, e}
    end
  end

  @spec create_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(attrs) do
    %Event{}
    |> Event.changeset(normalize_attrs(attrs))
    |> Repo.insert()
  end

  @spec update_event(Event.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(normalize_attrs(attrs))
    |> Repo.update()
  end

  defp normalize_attrs(attrs) do
    case Map.get(attrs, "config") || Map.get(attrs, :config) do
      nil ->
        attrs

      cfg when is_binary(cfg) ->
        case Jason.decode(cfg) do
          {:ok, parsed} -> Map.put(attrs, "config", Config.normalize(parsed))
          _ -> attrs
        end

      cfg when is_map(cfg) ->
        Map.put(attrs, "config", Config.normalize(cfg))
    end
  end

  @spec list_registrations(Ecto.UUID.t()) :: [EventRegistration.t()]
  def list_registrations(event_id) do
    from(r in EventRegistration,
      where: r.event_id == ^event_id,
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
  end

  @spec register(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, EventRegistration.t()} | {:error, registration_error()}
  def register(event_id, user_id, squad_id) do
    with {:ok, event} <- get_event(event_id),
         :ok <- ensure_signup_open(event),
         :ok <- ensure_not_registered(event_id, user_id),
         {:ok, squad} <- fetch_squad(user_id, squad_id),
         :ok <- Eligibility.check(event, user_id, squad),
         fee <- Map.get(event.config || %{}, "entry_fee_coins", 0),
         :ok <- ensure_funds(user_id, fee),
         :ok <- Wallet.debit(user_id, %{coins: fee}) do
      result =
        Repo.transaction(fn ->
          {:ok, reg} =
            %EventRegistration{}
            |> EventRegistration.changeset(%{
              event_id: event_id,
              user_id: user_id,
              status: :registered
            })
            |> Repo.insert()

          {:ok, _msg} =
            %InboxMessage{}
            |> InboxMessage.changeset(%{
              user_id: user_id,
              title: "Registered for event",
              body: "You're signed up for #{event.name}.",
              type: "event_signup",
              data: %{event_id: event_id, squad_id: squad_id, fee: fee}
            })
            |> Repo.insert()

          reg
        end)

      case result do
        {:ok, reg} -> {:ok, reg}
        {:error, _} = err -> err
      end
    end
  end

  defp ensure_signup_open(%Event{} = event) do
    now = DateTime.utc_now()
    cfg = event.config || %{}
    signup_end = Map.get(cfg, "signup_ends_at") || event.start_time

    cond do
      not event.active -> {:error, :event_closed}
      DateTime.compare(now, event.start_time) != :lt -> {:error, :event_closed}
      DateTime.compare(now, signup_end) != :lt -> {:error, :event_closed}
      true -> :ok
    end
  end

  defp ensure_not_registered(event_id, user_id) do
    case Repo.get_by(EventRegistration, event_id: event_id, user_id: user_id) do
      nil -> :ok
      _ -> {:error, :already_registered}
    end
  end

  defp ensure_funds(user_id, fee) when fee > 0 do
    case Wallet.ensure_affordable(user_id, %{coins: fee}) do
      :ok -> :ok
      _ -> {:error, :insufficient_funds}
    end
  end

  defp ensure_funds(_user_id, _fee), do: :ok

  defp fetch_squad(user_id, squad_id) do
    case Squads.get_user_squad(user_id, squad_id) do
      {:ok, squad} -> {:ok, squad}
      {:error, _} -> {:error, :invalid_squad}
    end
  end

  @spec start_now(Ecto.UUID.t()) :: :ok | {:error, atom()}
  def start_now(event_id) do
    case get_event(event_id) do
      {:ok, event} -> Runner.start_event(event)
      err -> err
    end
  end
end
