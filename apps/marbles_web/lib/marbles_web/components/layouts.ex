defmodule MarblesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MarblesWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :any, default: nil
  attr :current_scope, :any, default: nil
  attr :wide, :boolean, default: false, doc: "use wider max-width for admin pages"
  attr :breadcrumbs, :list, default: [], doc: "list of {label, path} or {label, nil} for current"
  slot :inner_block, required: true

  def app(assigns) do
    wide = Map.get(assigns, :wide, false)
    max_width = if wide, do: "max-w-6xl", else: "max-w-2xl"
    breadcrumbs = Map.get(assigns, :breadcrumbs, [])
    assigns = assign(assigns, :main_max_width, max_width)
    assigns = assign(assigns, :breadcrumbs, breadcrumbs)

    ~H"""
    <header class="sticky top-0 z-40 flex items-center justify-between gap-4 border-b border-base-300 bg-base-100/95 backdrop-blur px-4 py-3 sm:px-6 lg:px-8">
      <a
        href={~p"/"}
        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-base-200 transition-colors"
        aria-label="Home"
      >
        <.icon name="hero-home" class="size-6 text-base-content/80" />
      </a>
      <div class="flex items-center gap-2">
        <.theme_toggle />
        <input type="checkbox" id="nav-drawer" class="peer sr-only" />
        <label
          for="nav-drawer"
          class="flex h-10 w-10 cursor-pointer items-center justify-center rounded-full hover:bg-base-200 transition-colors md:hidden"
          aria-label="Menu"
        >
          <.icon name="hero-bars-3" class="size-6" />
        </label>
        <div
          class="fixed inset-0 z-40 bg-black/50 opacity-0 pointer-events-none peer-checked:opacity-100 peer-checked:pointer-events-auto transition-opacity md:hidden"
          aria-hidden="true"
        >
          <label for="nav-drawer" class="absolute inset-0" />
        </div>
        <nav class="fixed top-0 right-0 z-50 h-full w-72 max-w-[85vw] bg-base-100 border-l border-base-300 shadow-xl translate-x-full peer-checked:translate-x-0 transition-transform duration-200 ease-out md:relative md:translate-x-0 md:w-auto md:border-0 md:shadow-none md:bg-transparent">
          <div class="flex items-center justify-between p-4 border-b border-base-300 md:hidden">
            <span class="font-medium">Menu</span>
            <label
              for="nav-drawer"
              class="flex h-10 w-10 cursor-pointer items-center justify-center rounded-full hover:bg-base-200"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </label>
          </div>
          <ul class="flex flex-col gap-1 p-4 md:flex-row md:items-center md:gap-3 md:p-0">
            <%= if @current_user do %>
              <li class="md:hidden">
                <span class="block px-3 py-2 text-sm text-base-content/70">
                  {Marbles.Accounts.primary_display_name(@current_user)}
                </span>
              </li>
              <%= if admin_or_owner?(@current_user) do %>
                <li>
                  <a
                    href={~p"/admin"}
                    class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                  >
                    Admin
                  </a>
                </li>
              <% end %>
              <%= if owner?(@current_user) do %>
                <li>
                  <a
                    href={~p"/admin/owner"}
                    class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                  >
                    Owner
                  </a>
                </li>
                <li>
                  <a
                    href={~p"/broadcast"}
                    class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                  >
                    Broadcast
                  </a>
                </li>
              <% end %>
              <li>
                <form action={~p"/logout"} method="post" class="block md:inline">
                  <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                  <input type="hidden" name="_method" value="delete" />
                  <button
                    type="submit"
                    class="w-full text-left rounded-lg px-3 py-2 hover:bg-base-200 md:w-auto md:px-2 md:py-1 md:text-sm"
                  >
                    Logout
                  </button>
                </form>
              </li>
            <% else %>
              <li>
                <a
                  href={~p"/login"}
                  class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                >
                  Login
                </a>
              </li>
            <% end %>
          </ul>
        </nav>
      </div>
    </header>

    <main class="px-4 py-6 sm:px-6 lg:px-8 min-h-[60vh]">
      <.breadcrumbs items={@breadcrumbs} />
      <div class={["mx-auto space-y-4", @main_max_width]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav :if={@items != []} class="mb-4 text-sm text-base-content/70" aria-label="Breadcrumb">
      <ol class="flex flex-wrap items-center gap-1.5">
        <li><a href={~p"/"} class="hover:text-base-content transition-colors">Home</a></li>
        <%= for {label, path} <- @items do %>
          <li class="flex items-center gap-1.5">
            <span class="text-base-content/50" aria-hidden="true">/</span>
            <%= if path do %>
              <a href={path} class="hover:text-base-content transition-colors">{label}</a>
            <% else %>
              <span class="text-base-content font-medium" aria-current="page">{label}</span>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end

  defp owner?(nil), do: false
  defp owner?(user), do: user.role == :owner

  defp admin_or_owner?(nil), do: false
  defp admin_or_owner?(user), do: user.role == :server_admin || owner?(user)

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="toast toast-bottom toast-end z-50" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
