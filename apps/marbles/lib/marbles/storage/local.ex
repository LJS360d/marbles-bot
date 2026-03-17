defmodule Marbles.Storage.Local do
  @behaviour Marbles.Storage

  def base_dir do
    Path.join([:code.priv_dir(:marbles_web), "static", "uploads"])
  end

  def put_file(binary, path) do
    upload_dir = base_dir()
    full = Path.join(upload_dir, path)
    dir = Path.dirname(full)
    File.mkdir_p!(dir)

    case File.write(full, binary) do
      :ok -> {:ok, path}
      error -> error
    end
  end

  def url(path) do
    "/uploads/#{path}"
  end

  def list_path(path) do
    full = if path == "", do: base_dir(), else: Path.join(base_dir(), path)

    unless File.exists?(full) do
      File.mkdir_p!(full)
    end

    case File.ls(full) do
      {:ok, names} ->
        entries =
          Enum.map(names, fn name ->
            item_path = if path == "", do: name, else: Path.join(path, name)
            full_path = Path.join(full, name)
            type = if File.dir?(full_path), do: :directory, else: :file
            %{name: name, path: item_path, type: type}
          end)
          |> Enum.sort_by(&{&1.type, String.downcase(&1.name)}, fn
            {:directory, _}, {:file, _} -> true
            {:file, _}, {:directory, _} -> false
            {_, a}, {_, b} -> a <= b
          end)

        {:ok, entries}

      err ->
        err
    end
  end

  def move(from, to) do
    base = base_dir()
    from_full = Path.join(base, from)
    to_full = Path.join(base, to)
    to_dir = Path.dirname(to_full)
    File.mkdir_p!(to_dir)
    File.rename(from_full, to_full)
  end
end
