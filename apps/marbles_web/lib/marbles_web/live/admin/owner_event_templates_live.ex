defmodule MarblesWeb.Admin.OwnerEventTemplatesLive do
  @moduledoc "Owner-only index of event templates (blueprints used by schedules)."

  use MarblesWeb, :live_view

  alias Marbles.Racing.{EventSchedules, EventTemplates}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Templates")
     |> assign(:current_scope, :owner_templates)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Templates", nil}])
     |> load_templates()}
  end

  defp load_templates(socket) do
    templates = EventTemplates.list_all()

    counts =
      templates
      |> Enum.map(&{&1.id, length(EventSchedules.list_by_template(&1.id))})
      |> Map.new()

    socket
    |> assign(:templates, templates)
    |> assign(:schedule_counts, counts)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, template} <- EventTemplates.get_template(id),
         {:ok, _} <- EventTemplates.delete_template(template) do
      {:noreply,
       socket
       |> put_flash(:info, "Template deleted.")
       |> load_templates()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete template.")}
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
          <h1 class="text-2xl font-bold">Event templates</h1>
          <.link
            navigate={~p"/admin/owner/templates/new"}
            class="btn btn-primary btn-sm rounded-full"
          >
            <.icon name="hero-plus" class="size-4" /> New
          </.link>
        </header>

        <p class="text-sm text-base-content/60 max-w-prose">
          Templates are blueprints used by recurring schedules. Each schedule clones a
          template into a live event at its cron tick.
        </p>

        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Name</th>
                <th>Type</th>
                <th>Duration</th>
                <th>Schedules</th>
                <th>Active</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={t <- @templates} id={"template-row-#{t.id}"}>
                <td class="font-medium">{t.name}</td>
                <td>{t.event_type}</td>
                <td class="text-xs text-base-content/60">
                  {format_duration(t.default_duration_seconds)}
                </td>
                <td>{Map.get(@schedule_counts, t.id, 0)}</td>
                <td>{if t.active, do: "yes", else: "no"}</td>
                <td class="text-right space-x-2">
                  <.link
                    navigate={~p"/admin/owner/templates/#{t.id}/edit"}
                    class="btn btn-ghost btn-xs"
                  >
                    Edit
                  </.link>
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={t.id}
                    data-confirm={"Delete template #{t.name}? Attached schedules will be removed."}
                    id={"delete-#{t.id}"}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
              <tr :if={@templates == []}>
                <td colspan="6" class="text-center text-base-content/60 py-6">
                  No templates yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_duration(seconds) when seconds >= 3600 do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    if m == 0, do: "#{h}h", else: "#{h}h #{m}m"
  end

  defp format_duration(seconds) when seconds >= 60, do: "#{div(seconds, 60)}m"
  defp format_duration(seconds), do: "#{seconds}s"
end
