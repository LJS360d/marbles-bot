defmodule MarblesWeb.Admin.OwnerEventEditLive do
  @moduledoc "Owner-only event create / edit form."

  use MarblesWeb, :live_view

  alias Marbles.Racing.{Events, Tracks, Weather}
  alias Marbles.Racing.Events.Config
  alias Marbles.Schema.Event

  @impl true
  def mount(params, _session, socket) do
    {event, action} =
      case params do
        %{"id" => id} ->
          {:ok, event} = Events.get_event(id)
          {event, :edit}

        _ ->
          {%Event{
             event_type: :scheduled_race,
             config: Config.defaults(),
             active: true,
             start_time: DateTime.add(DateTime.utc_now(), 60 * 60),
             end_time: DateTime.add(DateTime.utc_now(), 4 * 60 * 60)
           }, :new}
      end

    {:ok,
     socket
     |> assign(:page_title, if(action == :new, do: "New event", else: "Edit event"))
     |> assign(:current_scope, :owner_events)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Events", ~p"/admin/owner/events"},
       {if(action == :new, do: "New", else: "Edit"), nil}
     ])
     |> assign(:action, action)
     |> assign(:event, event)
     |> assign(:tracks, Tracks.all())
     |> assign(:weathers, Weather.all())
     |> assign_form()}
  end

  defp assign_form(socket) do
    cs = Event.changeset(socket.assigns.event, %{})
    assign(socket, :form, to_form(cs))
  end

  @impl true
  def handle_event("validate", %{"event" => attrs}, socket) do
    cs =
      socket.assigns.event
      |> Event.changeset(normalize_form(attrs))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs))}
  end

  def handle_event("save", %{"event" => attrs}, socket) do
    case persist(socket.assigns.action, socket.assigns.event, normalize_form(attrs)) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event saved.")
         |> push_navigate(to: ~p"/admin/owner/events")}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}
    end
  end

  defp persist(:new, _event, attrs), do: Events.create_event(attrs)
  defp persist(:edit, event, attrs), do: Events.update_event(event, attrs)

  defp normalize_form(attrs) do
    cfg = Map.get(attrs, "config_json")

    config =
      case cfg do
        nil ->
          %{}

        "" ->
          %{}

        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, parsed} -> parsed
            _ -> %{}
          end
      end

    attrs
    |> Map.put("config", Config.normalize(config))
    |> Map.delete("config_json")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={:owner_events}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="max-w-3xl space-y-5">
        <h1 class="text-2xl font-bold">{if @action == :new, do: "New event", else: "Edit event"}</h1>

        <.form
          for={@form}
          id="event-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} label="Name" />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <div class="grid gap-3 md:grid-cols-2">
            <.input field={@form[:start_time]} type="datetime-local" label="Start" />
            <.input field={@form[:end_time]} type="datetime-local" label="End" />
          </div>
          <.input
            field={@form[:event_type]}
            type="select"
            label="Type"
            options={[
              {"Scheduled race", "scheduled_race"},
              {"Tournament", "tournament"},
              {"Special event", "special_event"}
            ]}
          />
          <.input field={@form[:active]} type="checkbox" label="Active" />

          <div>
            <label class="label-text text-sm font-medium block mb-1">
              Config (JSON)
            </label>
            <textarea
              name="event[config_json]"
              class="textarea textarea-bordered w-full font-mono text-xs h-72"
              spellcheck="false"
              phx-debounce="500"
            >{Jason.encode!(@event.config || Marbles.Racing.Events.Config.defaults(), pretty: true)}</textarea>
            <p class="mt-1 text-xs text-base-content/60">
              Available track slugs: {tracks_list(@tracks)}
            </p>
            <p class="mt-1 text-xs text-base-content/60">
              Available weather keys: {weathers_list(@weathers)}
            </p>
          </div>

          <div class="flex gap-2 pt-2">
            <button type="submit" id="event-save" class="btn btn-primary btn-sm rounded-full">
              Save
            </button>
            <.link navigate={~p"/admin/owner/events"} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  defp tracks_list(tracks), do: tracks |> Enum.map(& &1.slug) |> Enum.join(", ")

  defp weathers_list(weathers),
    do: weathers |> Enum.map(&Atom.to_string(&1.key)) |> Enum.join(", ")
end
