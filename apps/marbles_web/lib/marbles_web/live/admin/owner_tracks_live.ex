defmodule MarblesWeb.Admin.OwnerTracksLive do
  @moduledoc "Owner-only index of race tracks (DB-defined + code-defined)."

  use MarblesWeb, :live_view

  alias Marbles.Audit
  alias Marbles.Racing.Tracks

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tracks")
     |> assign(:current_scope, :owner_tracks)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Tracks", nil}])
     |> load_tracks()}
  end

  defp load_tracks(socket) do
    db_tracks = Tracks.list_db_all()
    all_descriptors = Tracks.all()
    db_slugs = MapSet.new(db_tracks, & &1.slug)
    code_tracks = Enum.reject(all_descriptors, &MapSet.member?(db_slugs, &1.slug))

    socket
    |> assign(:db_tracks, db_tracks)
    |> assign(:code_tracks, code_tracks)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, track} <- Tracks.get_db(id),
         before <- Map.take(track, [:slug, :name, :active]),
         {:ok, _} <- Tracks.delete(track) do
      Audit.log("track.delete",
        actor_id: socket.assigns.current_user.id,
        target_type: "race_track",
        target_id: id,
        before: before
      )

      {:noreply,
       socket
       |> put_flash(:info, "Track deleted.")
       |> load_tracks()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete track.")}
    end
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
      <section class="space-y-5">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Tracks</h1>
          <.link navigate={~p"/admin/owner/tracks/new"} class="btn btn-primary btn-sm rounded-full">
            <.icon name="hero-plus" class="size-4" /> New
          </.link>
        </header>

        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Source</th>
                <th>Slug</th>
                <th>Name</th>
                <th>Length</th>
                <th>Laps</th>
                <th>Difficulty</th>
                <th>Active</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={t <- @db_tracks} id={"track-row-#{t.id}"}>
                <td><span class="badge badge-primary badge-xs">DB</span></td>
                <td class="font-mono text-xs">{t.slug}</td>
                <td class="font-medium">{t.name}</td>
                <td class="text-xs">{Float.round(t.length_meters || 0.0, 1)}m</td>
                <td class="text-xs">{t.laps}</td>
                <td class="text-xs">{t.difficulty}</td>
                <td>{if t.active, do: "yes", else: "no"}</td>
                <td class="text-right space-x-2">
                  <.link
                    navigate={~p"/admin/owner/tracks/#{t.id}/edit"}
                    class="btn btn-ghost btn-xs"
                  >
                    Edit
                  </.link>
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={t.id}
                    data-confirm={"Delete track #{t.name}?"}
                    id={"delete-#{t.id}"}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
              <tr :for={t <- @code_tracks} id={"track-code-#{t.slug}"}>
                <td><span class="badge badge-ghost badge-xs">code</span></td>
                <td class="font-mono text-xs">{t.slug}</td>
                <td class="font-medium">{t.name}</td>
                <td class="text-xs">{Float.round(t.length_meters || 0.0, 1)}m</td>
                <td class="text-xs">{t.laps}</td>
                <td class="text-xs">{t.difficulty}</td>
                <td>yes</td>
                <td class="text-right text-xs text-base-content/50">
                  (defined in code — edit module to change)
                </td>
              </tr>
              <tr :if={@db_tracks == [] and @code_tracks == []}>
                <td colspan="8" class="text-center text-base-content/60 py-6">
                  No tracks yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
