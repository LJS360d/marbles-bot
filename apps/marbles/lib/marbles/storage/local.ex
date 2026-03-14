defmodule Marbles.Storage.Local do
  @behaviour Marbles.Storage

  def put_file(binary, filename) do
    # Save to the web app's static directory
    upload_dir = Path.join([:code.priv_dir(:marbles_web), "static", "uploads"])
    File.mkdir_p!(upload_dir)

    path = Path.join(upload_dir, filename)

    case File.write(path, binary) do
      :ok -> {:ok, filename}
      error -> error
    end
  end

  def url(filename) do
    # Returns a relative path for the Phoenix endpoint to handle
    "/uploads/#{filename}"
  end
end
