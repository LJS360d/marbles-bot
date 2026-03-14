defmodule Marbles.Storage.S3 do
  @behaviour Marbles.Storage
  alias ExAws.S3

  def put_file(binary, filename) do
    bucket = System.get_env("S3_BUCKET", "bucket")

    bucket
    |> S3.put_object("uploads/#{filename}", binary)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, filename}
      {:error, reason} -> {:error, reason}
    end
  end

  def url(filename) do
    base_url = Application.get_env(:marbles, :assets_base_url)
    # Ensure base_url doesn't end with a slash for consistency
    "#{String.trim_trailing(base_url, "/")}/uploads/#{filename}"
  end
end
