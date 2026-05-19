defmodule MarblesWeb.Admin.OwnerEventTemplateEditLive do
  @moduledoc "Owner-only create / edit form for an event template."

  use MarblesWeb, :live_view

  alias Marbles.Racing.{EventTemplates, Tracks, Weather}
  alias Marbles.Racing.Events.Config
  alias Marbles.Schema.EventTemplate

  @impl true
  def mount(params, _session, socket) do
    {template, action} =
      case params do
        %{"id" => id} ->
          {:ok, tmpl} = EventTemplates.get_template(id)
          {tmpl, :edit}

        _ ->
          {%EventTemplate{
             event_type: :scheduled_race,
             config: Config.defaults(),
             active: true,
             default_duration_seconds: 3600
           }, :new}
      end

    {:ok,
     socket
     |> assign(:page_title, if(action == :new, do: "New template", else: "Edit template"))
     |> assign(:current_scope, :owner_templates)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Templates", ~p"/admin/owner/templates"},
       {if(action == :new, do: "New", else: "Edit"), nil}
     ])
     |> assign(:action, action)
     |> assign(:template, template)
     |> assign(:tracks, Tracks.all())
     |> assign(:weathers, Weather.all())
     |> assign_form()}
  end

  defp assign_form(socket) do
    cs = EventTemplate.changeset(socket.assigns.template, %{})
    assign(socket, :form, to_form(cs))
  end

  @impl true
  def handle_event("validate", %{"template" => attrs}, socket) do
    cs =
      socket.assigns.template
      |> EventTemplate.changeset(normalize_form(attrs))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs))}
  end

  def handle_event("save", %{"template" => attrs}, socket) do
    case persist(socket.assigns.action, socket.assigns.template, normalize_form(attrs)) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template saved.")
         |> push_navigate(to: ~p"/admin/owner/templates")}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}
    end
  end

  @impl true
  def handle_info({:file_picker_selected, "template-banner-picker", path}, socket) do
    cs = socket.assigns.form.source |> Ecto.Changeset.put_change(:banner_path, path)
    {:noreply, assign(socket, :form, to_form(cs))}
  end

  defp persist(:new, _tmpl, attrs), do: EventTemplates.create_template(attrs)
  defp persist(:edit, tmpl, attrs), do: EventTemplates.update_template(tmpl, attrs)

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
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="max-w-3xl space-y-6">
        <h1 class="text-2xl font-bold">
          {if @action == :new, do: "New template", else: "Edit template"}
        </h1>

        <.form
          for={@form}
          id="template-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} label="Name" />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <div class="flex gap-0 items-center">
            <div class="flex-1">
              <.input
                field={@form[:banner_path]}
                label="Banner path"
                placeholder="/images/banners/..."
                class="input w-full rounded-r-none"
              />
            </div>
            <div class="mt-[25px]">
              <.live_component
                module={MarblesWeb.Components.FilePicker}
                id="template-banner-picker"
                current_path={Ecto.Changeset.get_field(@form.source, :banner_path) || ""}
              />
            </div>
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

          <.input
            field={@form[:default_duration_seconds]}
            type="number"
            label="Default duration (seconds)"
          />
          <p class="text-xs text-base-content/50 -mt-2">
            Live event runs end this many seconds after their computed start_time.
          </p>

          <.input field={@form[:active]} type="checkbox" label="Active" />

          <div>
            <label class="label-text text-sm font-medium block mb-1">Config (JSON)</label>
            <textarea
              name="template[config_json]"
              class="textarea textarea-bordered w-full font-mono text-xs h-72"
              spellcheck="false"
              phx-debounce="500"
            >{Jason.encode!(@template.config || Marbles.Racing.Events.Config.defaults(), pretty: true)}</textarea>
            <p class="mt-1 text-xs text-base-content/60">
              Available track slugs: {tracks_list(@tracks)}
            </p>
            <p class="mt-1 text-xs text-base-content/60">
              Available weather keys: {weathers_list(@weathers)}
            </p>
          </div>

          <div class="flex gap-2 pt-2">
            <button type="submit" id="template-save" class="btn btn-primary btn-sm rounded-full">
              Save
            </button>
            <.link navigate={~p"/admin/owner/templates"} class="btn btn-ghost btn-sm">Cancel</.link>
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
