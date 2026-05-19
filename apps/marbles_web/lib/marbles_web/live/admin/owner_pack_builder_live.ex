defmodule MarblesWeb.Admin.OwnerPackBuilderLive do
  use MarblesWeb, :live_view
  alias Marbles.Packs
  alias Marbles.Schema.Pack

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

          rule_rows = rule_rows_from_rules(pack.pull_rules || [])

          assign(socket, pack: pack, form: form, marble_ids: marble_ids, rule_rows: rule_rows)
      end

    copy_rule_options =
      Packs.list_all_packs(order: :name)
      |> Enum.map(&{&1.name, &1.id})
      |> case do
        [] -> [{"No packs available", ""}]
        options -> options
      end

    default_copy_rule_pack_id =
      case copy_rule_options do
        [{_, id} | _] -> id
        _ -> ""
      end

    socket =
      socket
      |> assign(:copy_rule_options, copy_rule_options)
      |> assign(:copy_rule_pack_id, default_copy_rule_pack_id)
      |> assign(:copy_rule_dialog_open, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:file_picker_selected, "banner-picker", path}, socket) do
    changeset = socket.assigns.form.source |> Ecto.Changeset.put_change(:banner_path, path)
    {:noreply, assign(socket, :form, to_form(changeset, as: "pack"))}
  end

  def handle_info({:marble_selection_changed, ids}, socket) do
    {:noreply, assign(socket, :marble_ids, ids)}
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
  def handle_event("open_copy_rules_dialog", _params, socket) do
    {:noreply, assign(socket, :copy_rule_dialog_open, true)}
  end

  @impl true
  def handle_event("close_copy_rules_dialog", _params, socket) do
    {:noreply, assign(socket, :copy_rule_dialog_open, false)}
  end

  @impl true
  def handle_event("copy_rule_source_changed", %{"pack_id" => pack_id}, socket) do
    {:noreply, assign(socket, :copy_rule_pack_id, normalize_pack_id(pack_id))}
  end

  @impl true
  def handle_event("copy_rules_from_pack", %{"pack_id" => pack_id}, socket) do
    normalized_pack_id = normalize_pack_id(pack_id)

    copied_rows =
      case safe_get_pack(normalized_pack_id) do
        {:ok, source_pack} -> rule_rows_from_rules(source_pack.pull_rules || [])
        :error -> socket.assigns.rule_rows || []
      end

    message =
      if copied_rows == [] do
        "Source pack has no rules."
      else
        "Copied #{length(copied_rows)} pull rule(s)."
      end

    {:noreply,
     socket
     |> assign(:rule_rows, copied_rows)
     |> assign(:copy_rule_pack_id, normalized_pack_id)
     |> assign(:copy_rule_dialog_open, false)
     |> put_flash(:info, message)}
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

  defp offer_date_input(nil), do: ""

  defp offer_date_input(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date() |> Date.to_iso8601()
  rescue
    _ -> ""
  end

  defp offer_date_input(_), do: ""

  defp rule_rows_from_rules(rules) do
    Enum.map(rules, fn r ->
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
  end

  defp safe_get_pack(""), do: :error

  defp safe_get_pack(pack_id) when is_binary(pack_id) do
    try do
      {:ok, Packs.get_pack!(pack_id)}
    rescue
      Ecto.NoResultsError -> :error
    end
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

  defp normalize_pack_id(pack_id) when is_binary(pack_id), do: pack_id
  defp normalize_pack_id(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
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
            <div class="mt-[25px]">
              <.live_component
                module={MarblesWeb.Components.FilePicker}
                id="banner-picker"
                current_path={Ecto.Changeset.get_field(@form.source, :banner_path) || ""}
              />
            </div>
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
            <strong>Discount</strong>: % off with trigger (always, N uses per account, once per period, or every N <em>pull actions</em>—1× adds 1, 10× adds 10). <strong>Pity</strong>: counts <em>marbles</em>; each 1× is one marble, each 10× is ten marbles in order. After N consecutive marbles below the minimum ★ without a natural hit at/above that ★, the next marble is forced to that ★ or higher. Rules have no ordering; discounts combine in insertion order.
          </p>
          <div class="flex flex-wrap gap-2">
            <button type="button" phx-click="rule_add" class="btn btn-outline btn-sm">
              Add rule
            </button>
            <button type="button" phx-click="open_copy_rules_dialog" class="btn btn-ghost btn-sm">
              Copy rules from pack
            </button>
          </div>
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
                <div class="flex flex-col gap-1 min-w-48">
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
                <div class="flex flex-col gap-1 min-w-56">
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

        <.live_component
          module={MarblesWeb.Components.MarbleSelector}
          id="marble-selector"
          selected_ids={@marble_ids}
        />
      </div>

      <div :if={@copy_rule_dialog_open} id="copy-rules-modal" class="modal modal-open" role="dialog">
        <div class="modal-box max-w-md">
          <h3 class="text-lg font-semibold">Copy pull rules</h3>
          <p class="mt-1 text-sm text-base-content/70">
            Select a source pack. Existing rules in this editor will be replaced.
          </p>
          <.form
            for={%{}}
            id="copy-rules-form"
            phx-change="copy_rule_source_changed"
            phx-submit="copy_rules_from_pack"
            class="mt-4 space-y-4"
          >
            <.input
              type="select"
              name="pack_id"
              label="Source pack"
              options={@copy_rule_options}
              value={@copy_rule_pack_id}
            />
            <div class="modal-action mt-0">
              <button type="button" phx-click="close_copy_rules_dialog" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">Copy rules</button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="close_copy_rules_dialog">close</button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
