defmodule MarblesWeb.Live.AuthHooks do
  import Phoenix.Component
  import Phoenix.LiveView
  use MarblesWeb, :verified_routes

  alias Marbles.Racing.{Engine, Queue}

  @spec on_mount(:assign_current_user, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:assign_current_user, _params, session, socket) do
    user = MarblesWeb.Authz.fetch_current_user(session["user_id"])

    socket =
      socket
      |> assign(:current_user, user)
      |> assign_race_state()
      |> maybe_attach_queue_listener()

    {:cont, socket}
  end

  @spec on_mount(:require_owner, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_owner, _params, session, socket) do
    user = MarblesWeb.Authz.fetch_current_user(session["user_id"])

    if MarblesWeb.Authz.authorize(user, :owner) == :ok do
      {:cont, assign(socket, :current_user, user)}
    else
      {:halt,
       socket
       |> put_flash(:error, "Not authorized.")
       |> redirect(to: ~p"/")}
    end
  end

  defp assign_race_state(socket) do
    state =
      case socket.assigns[:current_user] do
        nil -> :idle
        user -> Queue.user_status(user.id)
      end

    state =
      case state do
        :idle -> :idle
        %{} -> :queued
      end

    assign(socket, :race_state, state)
  end

  defp maybe_attach_queue_listener(socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        socket

      not connected?(socket) ->
        socket

      true ->
        Phoenix.PubSub.subscribe(Marbles.PubSub, Queue.user_topic(user.id))

        attach_hook(socket, :race_state_listener, :handle_info, fn
          {:queued, _meta}, s ->
            {:halt,
             s
             |> assign(:race_state, :queued)
             |> put_flash(:info, "Queued. We'll let you know when your race starts.")}

          {:matched, race_id}, s ->
            if Engine.engine_running?(race_id) do
              {:halt,
               s
               |> assign(:race_state, :in_race)
               |> put_flash(:info, "Your race is starting!")}
            else
              {:halt, assign(s, :race_state, :in_race)}
            end

          {:left, _reason}, s ->
            {:halt, assign(s, :race_state, :idle)}

          _msg, s ->
            {:cont, s}
        end)
    end
  end
end
