defmodule MarblesWeb.Dev.SandboxLive do
  use MarblesWeb, :live_view

  alias Marbles.{Assets, Catalog}
  alias Marbles.Schema.Marble

  @sandbox_query_limit 500
  @sandbox_marble_limit 10

  @doc """
  Returns up to `limit` marbles that have a resolvable CDN texture URL, in stable catalog order.

  Used by the dev sandbox so the client only receives textured rows for physics preview.
  """
  @spec pick_textured_marbles_for_sandbox([Marble.t()], pos_integer()) :: [Marble.t()]
  def pick_textured_marbles_for_sandbox(marbles, limit)
      when is_list(marbles) and is_integer(limit) and limit > 0 do
    marbles
    |> Enum.filter(fn m -> Assets.marble_texture_url(m) != nil end)
    |> Enum.take(limit)
  end

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {marbles, total} =
      Catalog.list_marbles(
        page: 1,
        per_page: @sandbox_query_limit,
        sort: :name,
        order: :asc
      )

    picked = pick_textured_marbles_for_sandbox(marbles, @sandbox_marble_limit)

    payload =
      Enum.map(picked, fn m ->
        %{
          "id" => m.id,
          "name" => m.name,
          "rarity" => m.rarity,
          "texture_url" => Assets.marble_texture_url(m)
        }
      end)

    json = Jason.encode!(payload)
    marbles_b64 = Base.encode64(json)

    {:ok,
     socket
     |> assign(:page_title, "Dev · Sandbox")
     |> assign(:current_scope, :dev)
     |> assign(:marble_count, length(payload))
     |> assign(:total_marbles, total)
     |> assign(:sandbox_query_limit, @sandbox_query_limit)
     |> assign(:sandbox_marble_limit, @sandbox_marble_limit)
     |> assign(:marbles_b64, marbles_b64)}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <Layouts.header current_user={@current_user} />
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="grid min-h-[calc(100vh-8rem)] grid-cols-1 border-t border-base-300 md:grid-cols-2">
        <div
          id="dev-sandbox-root"
          phx-hook="DevSandbox"
          phx-update="ignore"
          data-marbles-b64={@marbles_b64}
          class="relative w-full min-h-80 h-[50svh] border-b border-base-300 bg-black md:h-[calc(100dvh-12rem)] md:min-h-[480px] md:border-b-0 md:border-r"
        >
        </div>
        <div class="overflow-y-auto p-4 text-sm space-y-3">
          <h1 class="text-lg font-semibold">Texture sandbox</h1>
          <p class="text-base-content/70">
            Orbit: drag rotate · wheel zoom · right-drag pan. Physics: {@marble_count} textured marbles (max {@sandbox_marble_limit}) from {@total_marbles} catalog (scanned {@sandbox_query_limit}).
          </p>
          <p class="text-xs text-base-content/50">
            Spheres + <code class="rounded bg-base-200 px-0.5">cannon-es</code>. Server picks textured rows via <code class="rounded bg-base-200 px-0.5">pick_textured_marbles_for_sandbox/2</code>. Edit <code class="rounded bg-base-200 px-1">dev_sandbox_hook.js</code>.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
