defmodule MarblesWeb.Admin.OwnerAbilitiesLive do
  @moduledoc "Owner-only read-only view of registered marble abilities."

  use MarblesWeb, :live_view

  alias Marbles.Racing.Abilities

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Abilities")
     |> assign(:current_scope, :owner_abilities)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Abilities", nil}])
     |> assign(:user_abilities, Abilities.all() |> Enum.map(&describe/1))
     |> assign(:auto_abilities, Abilities.auto() |> Enum.map(&describe/1))}
  end

  defp describe(mod) do
    %{
      module: mod,
      key: mod.key(),
      name: try_call(mod, :name, mod |> Module.split() |> List.last()),
      description: try_call(mod, :description, "—")
    }
  end

  defp try_call(mod, fun, default) do
    if function_exported?(mod, fun, 0), do: apply(mod, fun, []), else: default
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
      <section class="space-y-6">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Abilities</h1>
          <span class="text-xs text-base-content/60">
            Code-defined. Add a module under `Marbles.Racing.Abilities.*` and register it.
          </span>
        </header>

        <div>
          <h2 class="text-lg font-semibold mb-2">User-assignable</h2>
          <div class="grid gap-3 md:grid-cols-2">
            <div
              :for={a <- @user_abilities}
              id={"ability-#{a.key}"}
              class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-1"
            >
              <div class="flex items-center justify-between">
                <h3 class="font-semibold">{a.name}</h3>
                <span class="font-mono text-xs text-base-content/50">{a.key}</span>
              </div>
              <p class="text-xs text-base-content/70">{a.description}</p>
              <p class="font-mono text-[10px] text-base-content/40">{inspect(a.module)}</p>
            </div>
          </div>
        </div>

        <div>
          <h2 class="text-lg font-semibold mb-2">Auto-applied</h2>
          <div class="grid gap-3 md:grid-cols-2">
            <div
              :for={a <- @auto_abilities}
              id={"ability-auto-#{a.key}"}
              class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-1"
            >
              <div class="flex items-center justify-between">
                <h3 class="font-semibold">{a.name}</h3>
                <span class="font-mono text-xs text-base-content/50">{a.key}</span>
              </div>
              <p class="text-xs text-base-content/70">{a.description}</p>
              <p class="font-mono text-[10px] text-base-content/40">{inspect(a.module)}</p>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
