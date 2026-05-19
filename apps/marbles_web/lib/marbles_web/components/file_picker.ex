defmodule MarblesWeb.Components.FilePicker do
  @moduledoc """
  S3-bucket file browser and uploader LiveComponent.

  Renders a "Browse" trigger button and a modal. On file selection, sends
  `{:file_picker_selected, id, path}` to the parent LiveView, where `id` is
  the component's `id` attribute so the parent can distinguish multiple pickers.

  ## Usage

      <.live_component
        module={MarblesWeb.Components.FilePicker}
        id="banner-picker"
        current_path={Ecto.Changeset.get_field(@form.source, :banner_path) || ""}
      />

  Parent LiveView must implement:

      @impl true
      def handle_info({:file_picker_selected, "banner-picker", path}, socket) do
        ...
      end
  """

  use MarblesWeb, :live_component
  alias Marbles.Storage

  @type entry :: %{type: :file | :directory, path: String.t(), name: String.t()}

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:path, fn -> "" end)
      |> assign_new(:entries, fn -> [] end)
      |> assign_new(:move_from, fn -> nil end)
      |> allow_upload(:bucket_file, accept: :any, max_entries: 1)

    {:ok, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("open", _params, socket) do
    current = socket.assigns[:current_path] || ""
    dir = if current == "", do: "", else: Path.dirname(current)

    {:noreply,
     socket
     |> assign(:open, true)
     |> assign(:path, dir)
     |> assign(:move_from, nil)
     |> load_entries()}
  end

  def handle_event("close", _params, socket) do
    {:noreply,
     socket
     |> assign(:open, false)
     |> cancel_all_uploads()}
  end

  def handle_event("navigate", %{"path" => path}, socket) do
    {:noreply,
     socket
     |> assign(:path, path)
     |> assign(:move_from, nil)
     |> load_entries()}
  end

  def handle_event("select", %{"path" => path}, socket) do
    send(self(), {:file_picker_selected, socket.assigns.id, path})

    {:noreply,
     socket
     |> assign(:open, false)
     |> cancel_all_uploads()}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("confirm_upload", _params, socket) do
    path_prefix = socket.assigns.path || ""

    result =
      consume_uploaded_entries(socket, :bucket_file, fn %{path: tmp_path}, entry ->
        filename = Path.basename(entry.client_name)
        dest = if path_prefix == "", do: filename, else: Path.join(path_prefix, filename)
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
      |> load_entries()

    {:noreply, socket}
  end

  def handle_event("move", %{"from" => from, "to" => to}, socket) do
    case Storage.move(from, to) do
      :ok ->
        {:noreply,
         socket
         |> assign(:move_from, nil)
         |> load_entries()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Move failed.")}
    end
  end

  def handle_event("set_move_from", %{"path" => path}, socket) do
    {:noreply, assign(socket, :move_from, path)}
  end

  def handle_event("clear_move", _params, socket) do
    {:noreply, assign(socket, :move_from, nil)}
  end

  @spec load_entries(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_entries(socket) do
    path = socket.assigns.path || ""

    case Storage.list_path(path) do
      {:ok, entries} -> assign(socket, :entries, entries)
      {:error, _} -> assign(socket, :entries, [])
    end
  end

  @spec cancel_all_uploads(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp cancel_all_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.bucket_file.entries, socket, fn entry, s ->
      Phoenix.LiveView.cancel_upload(s, :bucket_file, entry.ref)
    end)
  end

  @spec upload_error_message(term()) :: String.t()
  defp upload_error_message({:http_error, _status, %{body: body}}) when is_binary(body) do
    case Regex.run(~r/<Message>(.*?)<\/Message>/s, body) do
      [_, msg] -> String.trim(msg)
      _ -> "Access Denied"
    end
  end

  defp upload_error_message({:http_error, status, _}), do: "HTTP #{status}"
  defp upload_error_message(other), do: inspect(other)

  @spec breadcrumbs(String.t() | nil) :: [{String.t(), String.t()}]
  defp breadcrumbs(path) do
    bucket_name = Application.get_env(:marbles, :s3_bucket) || "root"

    if path == "" or path == nil do
      [{"", bucket_name}]
    else
      parts = String.split(path, "/", trim: true)

      [
        {"", bucket_name}
        | Enum.with_index(parts)
          |> Enum.map(fn {p, i} -> {Enum.take(parts, i + 1) |> Enum.join("/"), p} end)
      ]
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <button
        type="button"
        phx-click="open"
        phx-target={@myself}
        class="btn btn-outline border-base-content/20 btn-md gap-1.5"
      >
        <.icon name="hero-folder-open" class="w-4 h-4" /> Browse
      </button>

      <div :if={@open} id={"#{@id}-modal"} class="modal modal-open" role="dialog">
        <div class="modal-box max-w-2xl max-h-[80vh] flex flex-col">
          <h3 class="font-semibold text-lg mb-2">Choose file from bucket</h3>
          <div class="flex flex-wrap gap-1 mb-2">
            <%= for {path, name} <- breadcrumbs(@path) do %>
              <button
                type="button"
                phx-click="navigate"
                phx-value-path={path}
                phx-target={@myself}
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
                <tr :for={e <- @entries}>
                  <td class="py-1">
                    <%= if e.type == :directory do %>
                      <div class="flex items-center justify-between gap-2">
                        <button
                          type="button"
                          phx-click="navigate"
                          phx-value-path={e.path}
                          phx-target={@myself}
                          class="flex items-center gap-1 hover:underline"
                        >
                          <.icon name="hero-folder" class="w-4 h-4" />
                          {e.name}
                        </button>
                        <button
                          :if={@move_from != nil}
                          type="button"
                          phx-click="move"
                          phx-value-from={@move_from}
                          phx-value-to={Path.join(e.path, Path.basename(@move_from))}
                          phx-target={@myself}
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
                            phx-click="select"
                            phx-value-path={e.path}
                            phx-target={@myself}
                            class="btn btn-primary btn-xs"
                          >
                            Select
                          </button>
                          <button
                            :if={@move_from == nil}
                            type="button"
                            phx-click="set_move_from"
                            phx-value-path={e.path}
                            phx-target={@myself}
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
          <div :if={@move_from != nil} class="alert alert-info py-1 mb-2">
            <span>Moving: {@move_from}</span>
            <button
              type="button"
              phx-click="clear_move"
              phx-target={@myself}
              class="btn btn-ghost btn-xs"
            >
              Cancel move
            </button>
          </div>
          <form
            id={"#{@id}-upload-form"}
            phx-change="validate"
            phx-submit="confirm_upload"
            phx-target={@myself}
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
            <button type="button" phx-click="close" phx-target={@myself} class="btn">Close</button>
          </div>
        </div>
        <div class="modal-backdrop" phx-drop-target={@uploads.bucket_file.ref}>
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="btn btn-sm btn-circle absolute right-2 top-2"
          >
            ✕
          </button>
        </div>
      </div>
    </div>
    """
  end
end
