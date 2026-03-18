defmodule MarblesWeb.Admin.OwnerPackBuilderLive do
  use MarblesWeb, :live_view
  alias Marbles.Packs
  alias Marbles.Catalog
  alias Marbles.Schema.Pack
  alias Marbles.Storage

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Pack")
      |> assign(:current_scope, :owner_admin)
      |> assign(:breadcrumbs, [
        {"Owner", ~p"/admin/owner"},
        {"Packs", ~p"/admin/owner/packs"},
        {"Pack", nil}
      ])
      |> assign(:wide, true)
      |> assign(:file_picker_open, false)
      |> assign(:file_picker_path, "")
      |> assign(:file_picker_entries, [])
      |> assign(:file_picker_move_from, nil)
      |> allow_upload(:bucket_file, accept: :any, max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case params["id"] do
        nil ->
          form = %Pack{} |> Pack.changeset(%{}) |> to_form(as: "pack")
          assign(socket, pack: nil, form: form, marble_ids: [])

        id ->
          pack = Packs.get_pack!(id)
          marble_ids = Enum.map(pack.marbles || [], & &1.id)

          form =
            pack
            |> Pack.changeset(%{
              name: pack.name,
              description: pack.description,
              cost: pack.cost,
              start_date: pack.start_date,
              end_date: pack.end_date,
              banner_path: pack.banner_path
            })
            |> to_form(as: "pack")

          assign(socket, pack: pack, form: form, marble_ids: marble_ids)
      end

    marbles = Catalog.list_marbles(per_page: 500) |> elem(0)
    teams = Catalog.list_teams()

    socket =
      socket
      |> assign(:marbles, marbles)
      |> assign(:teams, teams)
      |> assign(:marble_search, "")
      |> assign(:marble_filter_team_id, nil)
      |> assign(:marble_filter_rarity, nil)
      |> assign(:filtered_marbles, apply_marble_filters(marbles, "", nil, nil))
      |> assign_new(:file_picker_open, fn -> false end)
      |> assign_new(:file_picker_path, fn -> "" end)
      |> assign_new(:file_picker_entries, fn -> [] end)
      |> assign_new(:file_picker_move_from, fn -> nil end)

    {:noreply, socket}
  end

  defp load_file_picker_entries(socket) do
    path = socket.assigns.file_picker_path || ""

    case Storage.list_path(path) do
      {:ok, entries} ->
        assign(socket, :file_picker_entries, entries)

      {:error, _} ->
        assign(socket, :file_picker_entries, [])
    end
  end

  defp upload_error_message({:http_error, _status, %{body: body}}) when is_binary(body) do
    case Regex.run(~r/<Message>(.*?)<\/Message>/s, body) do
      [_, msg] -> String.trim(msg)
      _ -> "Access Denied"
    end
  end

  defp upload_error_message({:http_error, status, _}), do: "HTTP #{status}"
  defp upload_error_message(other), do: inspect(other)

  defp file_picker_breadcrumbs(path) do
    bucket_name = Application.get_env(:marbles, :s3_bucket) || "root"

    if path == "" or path == nil do
      [{"", bucket_name}]
    else
      parts = path |> String.split("/", trim: true)

      [
        {"", bucket_name}
        | Enum.with_index(parts)
          |> Enum.map(fn {p, i} -> {Enum.take(parts, i + 1) |> Enum.join("/"), p} end)
      ]
    end
  end

  defp apply_marble_filters(marbles, search, team_id, rarity) do
    marbles
    |> Enum.filter(fn m ->
      (search == "" or String.contains?(String.downcase(m.name), String.downcase(search))) and
        (is_nil(team_id) or (m.team_id && m.team_id == team_id)) and
        (is_nil(rarity) or m.rarity == rarity)
    end)
  end

  @impl true
  def handle_event("validate", %{"pack" => params}, socket) do
    changeset =
      (socket.assigns.pack || %Pack{})
      |> Pack.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "pack"))}
  end

  @impl true
  def handle_event("save", %{"pack" => params}, socket) do
    marble_ids = socket.assigns.marble_ids || []

    result =
      if socket.assigns.pack do
        socket.assigns.pack
        |> Packs.update_pack(params)
        |> case do
          {:ok, pack} -> Packs.set_pack_marbles(pack, marble_ids)
          err -> err
        end
      else
        case Packs.create_pack(params) do
          {:ok, pack} -> Packs.set_pack_marbles(pack, marble_ids)
          err -> err
        end
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pack saved.")
         |> push_navigate(to: ~p"/admin/owner/packs")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "pack"))}
    end
  end

  @impl true
  def handle_event("toggle_marble", %{"id" => id}, socket) do
    ids = socket.assigns.marble_ids
    marble_ids = if id in ids, do: List.delete(ids, id), else: [id | ids]
    {:noreply, assign(socket, marble_ids: marble_ids)}
  end

  @impl true
  def handle_event("marble_filter", params, socket) do
    q = Map.get(params, "q", "") || ""

    team_id =
      case params["team_id"] do
        "" -> nil
        id -> id
      end

    rarity =
      case params["rarity"] do
        "" -> nil
        r -> String.to_integer(r)
      end

    marbles = socket.assigns.marbles

    {:noreply,
     socket
     |> assign(:marble_search, q)
     |> assign(:marble_filter_team_id, team_id)
     |> assign(:marble_filter_rarity, rarity)
     |> assign(:filtered_marbles, apply_marble_filters(marbles, q, team_id, rarity))}
  end

  @impl true
  def handle_event("file_picker_validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_all_shown", _params, socket) do
    ids = Enum.map(socket.assigns.filtered_marbles, & &1.id)
    current = socket.assigns.marble_ids
    marble_ids = Enum.uniq(ids ++ current)
    {:noreply, assign(socket, marble_ids: marble_ids)}
  end

  @impl true
  def handle_event("deselect_all_shown", _params, socket) do
    remove_ids = MapSet.new(Enum.map(socket.assigns.filtered_marbles, & &1.id))
    marble_ids = Enum.reject(socket.assigns.marble_ids, &(&1 in remove_ids))
    {:noreply, assign(socket, marble_ids: marble_ids)}
  end

  @impl true
  def handle_event("select_all_team", %{"team_id" => team_id}, socket) do
    team_ids = Enum.filter(socket.assigns.marbles, &(&1.team_id == team_id)) |> Enum.map(& &1.id)
    marble_ids = Enum.uniq((socket.assigns.marble_ids || []) ++ team_ids)
    {:noreply, assign(socket, marble_ids: marble_ids)}
  end

  @impl true
  def handle_event("deselect_all_team", %{"team_id" => team_id}, socket) do
    remove_ids =
      MapSet.new(
        Enum.filter(socket.assigns.marbles, &(&1.team_id == team_id))
        |> Enum.map(& &1.id)
      )

    marble_ids = Enum.reject(socket.assigns.marble_ids, &(&1 in remove_ids))
    {:noreply, assign(socket, marble_ids: marble_ids)}
  end

  @impl true
  def handle_event("open_file_picker", _params, socket) do
    current = Ecto.Changeset.get_field(socket.assigns.form.source, :banner_path) || ""
    dir = if current == "", do: "", else: Path.dirname(current)

    {:noreply,
     socket
     |> assign(:file_picker_open, true)
     |> assign(:file_picker_path, dir)
     |> assign(:file_picker_move_from, nil)
     |> load_file_picker_entries()}
  end

  @impl true
  def handle_event("close_file_picker", _params, socket) do
    socket = assign(socket, :file_picker_open, false)

    socket =
      Enum.reduce(socket.assigns.uploads.bucket_file.entries, socket, fn entry, s ->
        Phoenix.LiveView.cancel_upload(s, :bucket_file, entry.ref)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("file_picker_navigate", %{"path" => path}, socket) do
    {:noreply,
     socket
     |> assign(:file_picker_path, path)
     |> assign(:file_picker_move_from, nil)
     |> load_file_picker_entries()}
  end

  @impl true
  def handle_event("file_picker_select", %{"path" => path}, socket) do
    changeset = socket.assigns.form.source |> Ecto.Changeset.put_change(:banner_path, path)

    socket =
      socket
      |> assign(:form, to_form(changeset, as: "pack"))
      |> assign(:file_picker_open, false)

    socket =
      Enum.reduce(socket.assigns.uploads.bucket_file.entries, socket, fn entry, s ->
        Phoenix.LiveView.cancel_upload(s, :bucket_file, entry.ref)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("file_picker_confirm_upload", _params, socket) do
    path_prefix = socket.assigns.file_picker_path || ""
    dest_path = if path_prefix == "", do: "", else: path_prefix

    result =
      consume_uploaded_entries(socket, :bucket_file, fn %{path: tmp_path}, entry ->
        filename = entry.client_name |> Path.basename()
        dest = if dest_path == "", do: filename, else: Path.join(dest_path, filename)
        binary = File.read!(tmp_path)

        case Storage.put_file(binary, dest) do
          {:ok, _} -> {:ok, dest}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    socket =
      case Enum.find(result, &match?({:error, _}, &1)) do
        {:error, reason} ->
          put_flash(socket, :error, "Upload failed: #{upload_error_message(reason)}")

        nil ->
          socket
      end
      |> load_file_picker_entries()

    {:noreply, socket}
  end

  @impl true
  def handle_event("file_picker_move", %{"from" => from, "to" => to}, socket) do
    case Storage.move(from, to) do
      :ok ->
        {:noreply,
         socket
         |> assign(:file_picker_move_from, nil)
         |> load_file_picker_entries()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Move failed.")}
    end
  end

  @impl true
  def handle_event("file_picker_set_move_from", %{"path" => path}, socket) do
    {:noreply, assign(socket, :file_picker_move_from, path)}
  end

  @impl true
  def handle_event("file_picker_clear_move", _params, socket) do
    {:noreply, assign(socket, :file_picker_move_from, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      wide={true}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <h1 class="text-2xl font-semibold">{if @pack, do: "Edit pack", else: "New pack"}</h1>

        <.form
          for={@form}
          id="pack-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input field={@form[:cost]} type="number" label="Cost" />
          <div class="flex gap-0 items-center mb-0">
            <div class="flex-1">
              <.input
                field={@form[:banner_path]}
                type="text"
                label="Banner path"
                class="input w-full rounded-r-none"
              />
            </div>
            <button
              type="button"
              phx-click="open_file_picker"
              class="btn btn-outline border-base-content/20 btn-md gap-1.5 mt-3.5 rounded-l-none"
            >
              <.icon name="hero-folder-open" class="w-4 h-4" /> Browse
            </button>
          </div>
          <p class="text-xs text-base-content/60">
            File path in the assets bucket (not full URL). Use Browse to pick or upload.
          </p>
          <.input field={@form[:start_date]} type="date" label="Start date" />
          <.input field={@form[:end_date]} type="date" label="End date" />

          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <.link navigate={~p"/admin/owner/packs"} class="btn btn-ghost">Cancel</.link>
          </div>
        </.form>

        <div class="fieldset border-t border-base-300 pt-6 mt-6" id="pack-marbles-fieldset">
          <span class="label mb-1">Marbles in pack</span>
          <p class="text-sm text-base-content/70 mb-2">
            {length(@marble_ids)} selected. Search and filter below, or use quick actions.
          </p>
          <form
            phx-change="marble_filter"
            id="marble-filter-form"
            class="flex flex-wrap items-center gap-2 mb-2"
          >
            <input
              type="text"
              name="q"
              value={@marble_search}
              phx-debounce="150"
              placeholder="Search by name..."
              class="input input-bordered input-sm w-44"
            />
            <select
              name="team_id"
              class="select select-bordered select-sm w-44"
            >
              <option value="">All teams</option>
              <option
                :for={t <- @teams}
                value={t.id}
                selected={@marble_filter_team_id == t.id}
              >
                {t.name}
              </option>
            </select>
            <select
              name="rarity"
              class="select select-bordered select-sm w-28"
            >
              <option value="">All rarities</option>
              <option value="1" selected={@marble_filter_rarity == 1}>R1</option>
              <option value="2" selected={@marble_filter_rarity == 2}>R2</option>
              <option value="3" selected={@marble_filter_rarity == 3}>R3</option>
            </select>
            <button type="button" phx-click="select_all_shown" class="btn btn-ghost btn-sm">
              Select all shown
            </button>
            <button type="button" phx-click="deselect_all_shown" class="btn btn-ghost btn-sm">
              Deselect all shown
            </button>
            <div class="dropdown dropdown-end">
              <label tabindex="0" class="btn btn-ghost btn-sm">Add whole team</label>
              <ul
                tabindex="0"
                class="dropdown-content menu z-10 rounded-box bg-base-200 p-2 shadow min-w-56 max-h-72 overflow-y-auto text-sm"
              >
                <li :for={t <- @teams}>
                  <button
                    type="button"
                    phx-click="select_all_team"
                    phx-value-team_id={t.id}
                    class="py-2 px-3"
                  >
                    {t.name}
                  </button>
                </li>
              </ul>
            </div>
            <div class="dropdown dropdown-end">
              <label tabindex="0" class="btn btn-ghost btn-sm">Remove whole team</label>
              <ul
                tabindex="0"
                class="dropdown-content menu z-10 rounded-box bg-base-200 p-2 shadow min-w-56 max-h-72 overflow-y-auto text-sm"
              >
                <li :for={t <- @teams}>
                  <button
                    type="button"
                    phx-click="deselect_all_team"
                    phx-value-team_id={t.id}
                    class="py-2 px-3"
                  >
                    {t.name}
                  </button>
                </li>
              </ul>
            </div>
          </form>
          <div class="max-h-64 overflow-y-auto rounded border border-base-300 p-2 space-y-1">
            <%= for m <- @filtered_marbles do %>
              <label
                for={"marble-#{m.id}"}
                class="flex items-center gap-2 cursor-pointer rounded px-2 py-1 hover:bg-base-200"
              >
                <input
                  type="checkbox"
                  id={"marble-#{m.id}"}
                  value={m.id}
                  checked={m.id in @marble_ids}
                  phx-click="toggle_marble"
                  phx-value-id={m.id}
                />
                <span>{m.name}</span>
                <span class="text-xs text-base-content/60">R{m.rarity}</span>
                <span :if={m.team} class="text-xs text-base-content/50">({m.team.name})</span>
              </label>
            <% end %>
          </div>
        </div>
      </div>

      <div :if={@file_picker_open} id="file-picker-modal" class="modal modal-open" role="dialog">
        <div class="modal-box max-w-2xl max-h-[80vh] flex flex-col">
          <h3 class="font-semibold text-lg mb-2">Choose file from bucket</h3>
          <div class="flex flex-wrap gap-1 mb-2">
            <%= for {path, name} <- file_picker_breadcrumbs(@file_picker_path) do %>
              <button
                type="button"
                phx-click="file_picker_navigate"
                phx-value-path={path}
                class="btn btn-ghost btn-xs"
              >
                {name}
              </button>
              <.icon :if={path != ""} name="hero-chevron-right" class="w-3 h-3 self-center" />
            <% end %>
          </div>
          <div class="flex-1 overflow-auto rounded border border-base-300 mb-2">
            <table class="table table-xs">
              <tbody>
                <tr :for={e <- @file_picker_entries}>
                  <td class="py-1">
                    <%= if e.type == :directory do %>
                      <div class="flex items-center justify-between gap-2">
                        <button
                          type="button"
                          phx-click="file_picker_navigate"
                          phx-value-path={e.path}
                          class="flex items-center gap-1 hover:underline"
                        >
                          <.icon name="hero-folder" class="w-4 h-4" />
                          {e.name}
                        </button>
                        <button
                          :if={@file_picker_move_from != nil}
                          type="button"
                          phx-click="file_picker_move"
                          phx-value-from={@file_picker_move_from}
                          phx-value-to={Path.join(e.path, Path.basename(@file_picker_move_from))}
                          class="btn btn-ghost btn-xs"
                        >
                          Move here
                        </button>
                      </div>
                    <% else %>
                      <div class="flex items-center justify-between gap-2">
                        <span class="flex items-center gap-1">
                          <.icon name="hero-document" class="w-4 h-4" />
                          {e.name}
                        </span>
                        <div class="flex gap-1">
                          <button
                            type="button"
                            phx-click="file_picker_select"
                            phx-value-path={e.path}
                            class="btn btn-primary btn-xs"
                          >
                            Select
                          </button>
                          <button
                            :if={@file_picker_move_from == nil}
                            type="button"
                            phx-click="file_picker_set_move_from"
                            phx-value-path={e.path}
                            class="btn btn-ghost btn-xs"
                          >
                            Move
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={@file_picker_move_from != nil} class="alert alert-info py-1 mb-2">
            <span>Moving: {@file_picker_move_from}</span>
            <button type="button" phx-click="file_picker_clear_move" class="btn btn-ghost btn-xs">
              Cancel move
            </button>
          </div>
          <form
            id="file-picker-upload"
            phx-change="file_picker_validate"
            phx-submit="file_picker_confirm_upload"
            class="flex flex-wrap items-end gap-2"
          >
            <div class="form-control">
              <label class="label py-0">
                <span class="label-text">Upload to current folder</span>
              </label>
              <.live_file_input
                upload={@uploads.bucket_file}
                class="file-input file-input-bordered file-input-sm w-full max-w-xs"
              />
            </div>
            <button
              type="submit"
              class="btn btn-sm btn-primary"
              disabled={Enum.empty?(@uploads.bucket_file.entries)}
            >
              Upload
            </button>
          </form>
          <div class="modal-action">
            <button type="button" phx-click="close_file_picker" class="btn">Close</button>
          </div>
        </div>
        <div class="modal-backdrop" phx-drop-target={@uploads.bucket_file.ref}>
          <button
            type="button"
            phx-click="close_file_picker"
            class="btn btn-sm btn-circle absolute right-2 top-2"
          >
            ✕
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
