defmodule MarblesWeb.Admin.OwnerTrackEditLive do
  @moduledoc "Owner-only create / edit form for a race track."

  use MarblesWeb, :live_view

  alias Marbles.Audit
  alias Marbles.Racing.Tracks
  alias Marbles.Schema.RaceTrack

  @impl true
  def mount(params, _session, socket) do
    {track, action} =
      case params do
        %{"id" => id} ->
          {:ok, t} = Tracks.get_db(id)
          {t, :edit}

        _ ->
          {%RaceTrack{
             length_meters: 1000.0,
             laps: 1,
             grid_size: 24,
             difficulty: 1,
             max_players: 100,
             active: true
           }, :new}
      end

    {:ok,
     socket
     |> assign(:page_title, if(action == :new, do: "New track", else: "Edit track"))
     |> assign(:current_scope, :owner_tracks)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Tracks", ~p"/admin/owner/tracks"},
       {if(action == :new, do: "New", else: "Edit"), nil}
     ])
     |> assign(:action, action)
     |> assign(:track, track)
     |> assign_form()}
  end

  defp assign_form(socket) do
    cs = RaceTrack.changeset(socket.assigns.track, %{})
    assign(socket, :form, to_form(cs))
  end

  @impl true
  def handle_event("validate", %{"race_track" => attrs}, socket) do
    cs =
      socket.assigns.track
      |> RaceTrack.changeset(normalize_form(attrs))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs))}
  end

  def handle_event("save", %{"race_track" => attrs}, socket) do
    attrs = normalize_form(attrs)

    case socket.assigns.action do
      :new ->
        case Tracks.create(attrs) do
          {:ok, t} ->
            Audit.log("track.create",
              actor_id: socket.assigns.current_user.id,
              target_type: "race_track",
              target_id: t.id,
              after: Map.take(t, [:slug, :name, :active])
            )

            {:noreply,
             socket
             |> put_flash(:info, "Track created.")
             |> push_navigate(to: ~p"/admin/owner/tracks")}

          {:error, cs} ->
            {:noreply, assign(socket, :form, to_form(cs))}
        end

      :edit ->
        before = Map.take(socket.assigns.track, [:slug, :name, :active, :difficulty])

        case Tracks.update(socket.assigns.track, attrs) do
          {:ok, t} ->
            Audit.log("track.update",
              actor_id: socket.assigns.current_user.id,
              target_type: "race_track",
              target_id: t.id,
              before: before,
              after: Map.take(t, [:slug, :name, :active, :difficulty])
            )

            {:noreply,
             socket
             |> put_flash(:info, "Track updated.")
             |> push_navigate(to: ~p"/admin/owner/tracks")}

          {:error, cs} ->
            {:noreply, assign(socket, :form, to_form(cs))}
        end
    end
  end

  defp normalize_form(attrs) do
    attrs
    |> normalize_json("start_positions_json", "start_positions")
    |> normalize_json("checkpoints_json", "checkpoints")
    |> normalize_json("finish_line_json", "finish_line")
    |> normalize_json("weather_bias_json", "weather_bias")
  end

  defp normalize_json(attrs, src, dst) do
    case Map.get(attrs, src) do
      nil ->
        attrs

      "" ->
        Map.put(attrs, dst, %{})

      s when is_binary(s) ->
        case Jason.decode(s) do
          {:ok, m} when is_map(m) -> Map.put(attrs, dst, m)
          _ -> attrs
        end
    end
    |> Map.delete(src)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="max-w-3xl space-y-6">
        <h1 class="text-2xl font-bold">
          {if @action == :new, do: "New track", else: "Edit track"}
        </h1>

        <.form
          for={@form}
          id="track-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <div class="grid gap-3 md:grid-cols-2">
            <.input field={@form[:slug]} label="Slug" placeholder="e.g. savage-speedway" />
            <.input field={@form[:name]} label="Name" />
          </div>
          <.input field={@form[:description]} type="textarea" label="Description" />
          <div class="grid gap-3 md:grid-cols-2">
            <.input field={@form[:track_model_path]} label="Model path" />
            <.input field={@form[:thumbnail_path]} label="Thumbnail path" />
          </div>
          <div class="grid gap-3 md:grid-cols-4">
            <.input field={@form[:length_meters]} type="number" step="0.1" label="Length (m)" />
            <.input field={@form[:laps]} type="number" label="Laps" />
            <.input field={@form[:grid_size]} type="number" label="Grid size" />
            <.input field={@form[:difficulty]} type="number" label="Difficulty (1-5)" />
          </div>
          <.input field={@form[:max_players]} type="number" label="Max players" />
          <.input field={@form[:active]} type="checkbox" label="Active" />

          <.json_block
            name="race_track[start_positions_json]"
            label="Start positions (JSON map)"
            value={@track.start_positions || %{}}
          />
          <.json_block
            name="race_track[checkpoints_json]"
            label="Checkpoints (JSON map)"
            value={@track.checkpoints || %{}}
          />
          <.json_block
            name="race_track[finish_line_json]"
            label="Finish line (JSON map with x and z)"
            value={@track.finish_line || %{}}
          />
          <.json_block
            name="race_track[weather_bias_json]"
            label="Weather bias (JSON: weather_key → multiplier)"
            value={@track.weather_bias || %{}}
          />

          <div class="flex gap-2 pt-2">
            <button type="submit" id="track-save" class="btn btn-primary btn-sm rounded-full">
              Save
            </button>
            <.link navigate={~p"/admin/owner/tracks"} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :map, required: true

  defp json_block(assigns) do
    ~H"""
    <div>
      <label class="label-text text-sm font-medium block mb-1">{@label}</label>
      <textarea
        name={@name}
        class="textarea textarea-bordered w-full font-mono text-xs h-32"
        spellcheck="false"
        phx-debounce="500"
      >{Jason.encode!(@value, pretty: true)}</textarea>
    </div>
    """
  end
end
