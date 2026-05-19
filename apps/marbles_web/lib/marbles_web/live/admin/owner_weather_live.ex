defmodule MarblesWeb.Admin.OwnerWeatherLive do
  @moduledoc "Owner-only read-only view of weather presets (code-defined)."

  use MarblesWeb, :live_view

  alias Marbles.Racing.Weather

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Weather")
     |> assign(:current_scope, :owner_weather)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Weather", nil}])
     |> assign(:weathers, Weather.all())}
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
          <h1 class="text-2xl font-bold">Weather presets</h1>
          <span class="text-xs text-base-content/60">
            Code-defined. Edit modules under `Marbles.Racing.Weather.*` to change.
          </span>
        </header>

        <div class="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          <div
            :for={w <- @weathers}
            id={"weather-card-#{w.key}"}
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-2"
          >
            <h2 class="font-semibold">{w.name}</h2>
            <p class="font-mono text-xs text-base-content/50">{w.key}</p>
            <div :if={w.modifiers != %{}} class="text-xs space-y-0.5">
              <p class="font-medium text-base-content/70">Modifiers</p>
              <ul class="font-mono">
                <li :for={{k, v} <- w.modifiers}>{k}: {inspect(v)}</li>
              </ul>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
