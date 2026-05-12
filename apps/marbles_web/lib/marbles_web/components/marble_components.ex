defmodule MarblesWeb.MarbleComponents do
  @moduledoc false

  use Phoenix.Component

  import MarblesWeb.CoreComponents

  @spec marble_info_payload(map() | nil) :: map() | nil
  def marble_info_payload(nil), do: nil

  def marble_info_payload(%{marble: m} = um) when not is_nil(m) do
    %{
      name: m.name,
      edition: m.edition,
      role: m.role,
      rarity: m.rarity,
      level: um.level,
      texture_path: m.texture_path,
      team_name: team_name(m),
      base_stats: m.base_stats || %{},
      abilities:
        case m.abilities do
          list when is_list(list) -> Enum.map(list, & &1.ability_key)
          _ -> []
        end
    }
  end

  def marble_info_payload(_), do: nil

  defp team_name(%{team: %{name: n}}) when is_binary(n), do: n
  defp team_name(_), do: nil

  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :marble, :map, default: nil
  attr :on_close, :string, required: true

  def marble_info_modal(assigns) do
    ~H"""
    <div
      :if={@show && @marble}
      id={@id}
      class="fixed inset-0 z-100 flex items-center justify-center p-4"
    >
      <div class="absolute inset-0 bg-base-content/50 backdrop-blur-sm" phx-click={@on_close} />
      <div class="relative z-101 w-full max-w-lg rounded-2xl border border-base-300 bg-base-100 p-5 shadow-2xl space-y-4">
        <header class="flex items-start justify-between gap-3">
          <div>
            <h3 class="text-lg font-bold">{@marble.name}</h3>
            <p class="text-xs uppercase tracking-wider text-base-content/60">
              {@marble.edition || "—"} · {format_role(@marble.role)} · ★{@marble.rarity}
            </p>
          </div>
          <button
            type="button"
            phx-click={@on_close}
            class="btn btn-ghost btn-sm btn-circle"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>

        <div :if={@marble.team_name} class="text-sm text-base-content/70">
          Team: <span class="font-medium text-base-content">{@marble.team_name}</span>
        </div>

        <div :if={@marble.level} class="text-sm">
          Collection level: <span class="font-mono font-semibold">{@marble.level}</span>
        </div>

        <div class="rounded-xl border border-base-300 bg-base-200/30 p-3 text-sm">
          <p class="text-xs uppercase tracking-wider text-base-content/60 mb-2">Base stats</p>
          <ul class="grid grid-cols-2 gap-x-3 gap-y-1 font-mono text-xs">
            <%= for {k, v} <- stat_entries(@marble.base_stats) do %>
              <li class="text-base-content/60">{k}</li>
              <li class="text-right">{v}</li>
            <% end %>
          </ul>
        </div>

        <div :if={@marble.abilities != []} class="text-sm">
          <p class="text-xs uppercase tracking-wider text-base-content/60 mb-1">Abilities</p>
          <p class="font-mono text-xs">{Enum.join(@marble.abilities, ", ")}</p>
        </div>
      </div>
    </div>
    """
  end

  defp format_role(nil), do: "—"
  defp format_role(r) when is_atom(r), do: Atom.to_string(r)
  defp format_role(r) when is_binary(r), do: r

  defp stat_entries(stats) when is_map(stats) do
    stats
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {k, v} ->
      {to_string(k), stat_fmt(v)}
    end)
  end

  defp stat_entries(_), do: []

  defp stat_fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp stat_fmt(v) when is_integer(v), do: Integer.to_string(v)
  defp stat_fmt(v), do: inspect(v)
end
