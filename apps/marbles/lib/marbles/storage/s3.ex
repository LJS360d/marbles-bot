defmodule Marbles.Storage.S3 do
  @behaviour Marbles.Storage
  require Logger
  alias ExAws.S3

  def bucket, do: System.get_env("S3_BUCKET", "bucket")

  def put_file(binary, path) do
    key = path

    bucket()
    |> S3.put_object(key, binary)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  def url(path) do
    base_url = Application.get_env(:marbles, :assets_base_url)
    "#{String.trim_trailing(base_url, "/")}/#{path}"
  end

  def list_path(path) do
    prefix = if path == "", do: "", else: "#{path}/"
    opts = [delimiter: "/", prefix: prefix]

    case bucket() |> S3.list_objects_v2(opts) |> ExAws.request() do
      {:ok, %{body: body}} ->
        prefixes = body |> get_list(:common_prefixes) |> Enum.map(&get_prefix/1)
        contents = body |> get_list(:contents) |> Enum.map(&get_key/1)

        dirs =
          prefixes
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn p ->
            item_path = String.trim_trailing(p, "/")

            name =
              if prefix == "",
                do: item_path,
                else: String.trim_leading(item_path, prefix) |> String.trim_leading("/")

            %{name: name, path: item_path, type: :directory}
          end)

        files =
          contents
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&String.ends_with?(&1, "/"))
          |> Enum.map(fn k ->
            name =
              if prefix == "",
                do: k,
                else: String.trim_leading(k, prefix) |> String.trim_leading("/")

            %{name: name, path: k, type: :file}
          end)

        entries =
          (dirs ++ files)
          |> Enum.sort_by(&{&1.type, String.downcase(&1.name)}, fn
            {:directory, _}, {:file, _} -> true
            {:file, _}, {:directory, _} -> false
            {_, a}, {_, b} -> a <= b
          end)

        Logger.info("#{inspect(entries)}")
        {:ok, entries}

      {:error, _} = err ->
        Logger.error("S3 list_objects 2: #{inspect(err)}")
        err
    end
  end

  defp get_list(body, key) do
    case body[key] || body[to_string(key)] do
      nil -> []
      list when is_list(list) -> list
      single -> [single]
    end
  end

  defp get_prefix(m) when is_map(m), do: m[:prefix] || m["prefix"]
  defp get_prefix(_), do: nil

  defp get_key(m) when is_map(m), do: m[:key] || m["key"]
  defp get_key(_), do: nil

  def move(from, to) do
    b = bucket()

    case S3.put_object_copy(b, to, b, from) |> ExAws.request() do
      {:ok, _} ->
        case b |> S3.delete_object(from) |> ExAws.request() do
          {:ok, _} -> :ok
          err -> err
        end

      err ->
        err
    end
  end
end
