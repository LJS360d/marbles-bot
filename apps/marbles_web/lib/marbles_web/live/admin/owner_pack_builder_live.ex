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
          assign(socket, pack: nil, form: form, marble_ids: [], rule_rows: [])

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

          rule_rows =
            Enum.map(pack.pull_rules || [], fn r ->
              scope =
                cond do
                  r.apply_1x && r.apply_10x -> "both"
                  r.apply_1x -> "1x_only"
                  true -> "10x_only"
                end

              %{
                effect_type: r.effect_type,
                discount_percent: r.discount_percent,
                min_rarity: r.min_rarity || 3,
                scope: scope,
                trigger_type: r.trigger_type,
                lifetime_max_uses: r.lifetime_max_uses || "",
                period_unit: r.period_unit || "day",
                every_n_pulls: r.every_n_pulls || 10,
                starts_at: offer_date_input(r.starts_at),
                ends_at: offer_date_input(r.ends_at)
              }
            end)

          assign(socket, pack: pack, form: form, marble_ids: marble_ids, rule_rows: rule_rows)
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

  defp offer_date_input(nil), do: ""

  defp offer_date_input(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date() |> Date.to_iso8601()
  rescue
    _ -> ""
  end

  defp offer_date_input(_), do: ""

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
    rule_rows = socket.assigns.rule_rows || []

    case Packs.save_pack_complete(socket.assigns.pack, params, marble_ids, rule_rows) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pack saved.")
         |> push_navigate(to: ~p"/admin/owner/packs")}

      {:error, {:rules, msg}} ->
        {:noreply, put_flash(socket, :error, msg)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "pack"))}
    end
  end

  @impl true
  def handle_event("rule_add", _, socket) do
    row = %{
      effect_type: "discount",
      discount_percent: 10,
      min_rarity: 3,
      scope: "both",
      trigger_type: "always",
      lifetime_max_uses: "",
      period_unit: "day",
      every_n_pulls: 10,
      starts_at: "",
      ends_at: ""
    }

    rows = socket.assigns.rule_rows || []
    {:noreply, assign(socket, :rule_rows, rows ++ [row])}
  end

  @impl true
  def handle_event("rule_remove", %{"idx" => idx}, socket) do
    i = String.to_integer(idx)
    rows = List.delete_at(socket.assigns.rule_rows || [], i)
    {:noreply, assign(socket, :rule_rows, rows)}
  end

  @impl true
  def handle_event("patch_rule", params, socket) do
    idx =
      case Integer.parse(to_string(params["idx"] || "0")) do
        {i, _} -> i
        :error -> 0
      end

    rows = socket.assigns.rule_rows || []

    case Enum.at(rows, idx) do
      nil ->
        {:noreply, socket}

      row ->
        eff = params["effect_type"] || row.effect_type

        trig =
          cond do
            eff == "pity" -> "every_n_pulls"
            row.effect_type == "pity" and eff == "discount" -> "always"
            true -> params["trigger_type"] || row.trigger_type
          end

        updated = %{
          effect_type: eff,
          discount_percent: parse_offer_int(params["discount_percent"], row.discount_percent),
          min_rarity: parse_offer_int(params["min_rarity"], row.min_rarity || 3),
          scope: params["scope"] || row.scope || "both",
          trigger_type: trig,
          lifetime_max_uses: params["lifetime_max_uses"] || row.lifetime_max_uses || "",
          period_unit: params["period_unit"] || row.period_unit || "day",
          every_n_pulls: parse_offer_int(params["every_n_pulls"], row.every_n_pulls || 10),
          starts_at: params["starts_at"] || row.starts_at || "",
          ends_at: params["ends_at"] || row.ends_at || ""
        }

        {:noreply, assign(socket, :rule_rows, List.replace_at(rows, idx, updated))}
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

  defp parse_offer_int(nil, d), do: d

  defp parse_offer_int(v, d) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} -> i
      :error -> d
    end
  end

  defp parse_offer_int(v, _) when is_integer(v), do: v
  defp parse_offer_int(_, d), do: d

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
        </.form>

        <div class="fieldset border border-base-300 rounded-lg p-4 space-y-3" id="pack-pull-rules">
          <span class="label">Pull rules</span>
          <p class="text-sm text-base-content/70 max-w-3xl leading-relaxed">
            <strong>Discount</strong>: % off with trigger (always, N uses per account, once per period, or every N <em>pull actions</em>—1× adds 1, 10× adds 10).
            <strong>Pity</strong>
            (max one per pack): counts <em>marbles</em>; each 1× is one marble, each 10× is ten marbles in order. After N consecutive marbles below the minimum ★ without a natural hit at/above that ★, the next marble is forced to that ★ or higher. Rules have no ordering; discounts combine in insertion order.
          </p>
          <button type="button" phx-click="rule_add" class="btn btn-outline btn-sm">
            Add rule
          </button>
          <div
            :for={{o, i} <- Enum.with_index(@rule_rows || [])}
            class={[
              "flex flex-col gap-3 p-4 rounded-xl border transition-shadow",
              o.effect_type == "pity" && "bg-amber-500/5 border-amber-500/20 shadow-sm",
              o.effect_type != "pity" && "bg-base-200/40 border-base-300"
            ]}
          >
            <form phx-change="patch_rule" id={"rule-row-#{i}"} class="flex flex-wrap items-end gap-3">
              <input type="hidden" name="idx" value={i} />
              <div class="flex flex-col gap-1">
                <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
                  Effect
                </span>
                <select name="effect_type" class="select select-bordered select-sm w-32">
                  <option value="discount" selected={o.effect_type == "discount"}>Discount</option>
                  <option value="pity" selected={o.effect_type == "pity"}>Pity</option>
                </select>
              </div>
              <%= if o.effect_type == "pity" do %>
                <input type="hidden" name="trigger_type" value="every_n_pulls" />
                <div class="flex flex-col gap-1 min-w-[12rem]">
                  <span class="text-xs font-medium text-base-content/50">Guarantee minimum ★</span>
                  <input
                    type="number"
                    name="min_rarity"
                    value={o.min_rarity}
                    min="1"
                    max="3"
                    class="input input-bordered input-sm w-full"
                  />
                </div>
                <div class="flex flex-col gap-1 min-w-[14rem]">
                  <span class="text-xs font-medium text-base-content/50">
                    Streak length (N marbles)
                  </span>
                  <input
                    type="number"
                    name="every_n_pulls"
                    value={o.every_n_pulls}
                    min="1"
                    class="input input-bordered input-sm w-full"
                  />
                  <span class="text-[11px] text-base-content/50">
                    Forced roll after N−1 below-min marbles in a row.
                  </span>
                </div>
              <% else %>
                <div class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-base-content/50">Discount %</span>
                  <input
                    type="number"
                    name="discount_percent"
                    value={o.discount_percent}
                    min="0"
                    max="100"
                    class="input input-bordered input-sm w-20"
                  />
                </div>
                <div class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-base-content/50">Scope</span>
                  <select name="scope" class="select select-bordered select-sm w-36">
                    <option value="both" selected={o.scope == "both"}>1× & 10×</option>
                    <option value="1x_only" selected={o.scope == "1x_only"}>1× only</option>
                    <option value="10x_only" selected={o.scope == "10x_only"}>10× only</option>
                  </select>
                </div>
                <div class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-base-content/50">Trigger</span>
                  <select name="trigger_type" class="select select-bordered select-sm w-44">
                    <option value="always" selected={o.trigger_type == "always"}>Always</option>
                    <option value="lifetime_uses" selected={o.trigger_type == "lifetime_uses"}>
                      N uses (account)
                    </option>
                    <option value="period_once" selected={o.trigger_type == "period_once"}>
                      Once per period
                    </option>
                    <option value="every_n_pulls" selected={o.trigger_type == "every_n_pulls"}>
                      Every N pull actions
                    </option>
                  </select>
                </div>
                <%= if o.trigger_type == "lifetime_uses" do %>
                  <div class="flex flex-col gap-1">
                    <span class="text-xs font-medium text-base-content/50">Max uses</span>
                    <input
                      type="number"
                      name="lifetime_max_uses"
                      value={o.lifetime_max_uses}
                      min="1"
                      class="input input-bordered input-sm w-20"
                      placeholder="N"
                    />
                  </div>
                <% else %>
                  <input type="hidden" name="lifetime_max_uses" value={o.lifetime_max_uses} />
                <% end %>
                <%= if o.trigger_type == "period_once" do %>
                  <div class="flex flex-col gap-1">
                    <span class="text-xs font-medium text-base-content/50">Period</span>
                    <select name="period_unit" class="select select-bordered select-sm w-28">
                      <option value="day" selected={o.period_unit == "day"}>Day</option>
                      <option value="week" selected={o.period_unit == "week"}>Week</option>
                      <option value="month" selected={o.period_unit == "month"}>Month</option>
                    </select>
                  </div>
                <% else %>
                  <input type="hidden" name="period_unit" value={o.period_unit} />
                <% end %>
                <%= if o.trigger_type == "every_n_pulls" do %>
                  <div class="flex flex-col gap-1">
                    <span class="text-xs font-medium text-base-content/50">N (pull actions)</span>
                    <input
                      type="number"
                      name="every_n_pulls"
                      value={o.every_n_pulls}
                      min="1"
                      class="input input-bordered input-sm w-20"
                    />
                  </div>
                <% else %>
                  <input type="hidden" name="every_n_pulls" value={o.every_n_pulls} />
                <% end %>
              <% end %>
              <div class="flex flex-col gap-1">
                <span class="text-xs font-medium text-base-content/50">Active from</span>
                <input
                  type="date"
                  name="starts_at"
                  value={o.starts_at}
                  class="input input-bordered input-sm w-36"
                />
              </div>
              <div class="flex flex-col gap-1">
                <span class="text-xs font-medium text-base-content/50">Active until</span>
                <input
                  type="date"
                  name="ends_at"
                  value={o.ends_at}
                  class="input input-bordered input-sm w-36"
                />
              </div>
            </form>
            <button
              type="button"
              phx-click="rule_remove"
              phx-value-idx={i}
              class="btn btn-ghost btn-sm text-error self-end"
            >
              Remove
            </button>
          </div>
        </div>

        <div class="flex gap-2">
          <button type="submit" form="pack-form" class="btn btn-primary">Save</button>
          <.link navigate={~p"/admin/owner/packs"} class="btn btn-ghost">Cancel</.link>
        </div>

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
