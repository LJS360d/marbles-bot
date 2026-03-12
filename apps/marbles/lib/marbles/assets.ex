defmodule Marbles.Assets do
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
end
