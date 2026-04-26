defmodule Marbles.Assets do
  alias Ecto.Association.NotLoaded
  alias Marbles.Schema.Marble

  def url_for_path(nil), do: nil
  def url_for_path(""), do: nil

  def url_for_path(path) when is_binary(path) do
    base = Application.get_env(:marbles, :assets_base_url)

    if base do
      base = String.trim_trailing(base, "/")
      path = String.trim_leading(path, "/")
      "#{base}/#{path}"
    else
      nil
    end
  end

  @doc """
  Resolves the CDN URL for a marble's diffuse texture.

  Uses `marble.texture_path` when set; otherwise derives
  `/.../standard/texture.png` from splash or thumbnail asset paths.
  """
  @spec marble_texture_url(Marble.t()) :: String.t() | nil
  def marble_texture_url(%Marble{assets: %NotLoaded{}} = marble) do
    url_for_path(marble.texture_path)
  end

  def marble_texture_url(%Marble{} = marble) do
    marble.texture_path
    |> Kernel.||(texture_path_from_assets(marble.assets))
    |> url_for_path()
  end

  defp texture_path_from_assets(assets) when is_list(assets) do
    case Enum.find(assets, &(&1.type == :splash && is_binary(&1.filename))) do
      %{filename: path} ->
        path |> Path.dirname() |> Path.join("texture.png")

      _ ->
        case Enum.find(assets, &(&1.type == :thumbnail && is_binary(&1.filename))) do
          %{filename: path} ->
            path |> Path.dirname() |> Path.join("texture.png")

          _ ->
            nil
        end
    end
  end

  defp texture_path_from_assets(_), do: nil
end
