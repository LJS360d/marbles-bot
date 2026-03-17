defmodule Marbles.Storage do
  @callback put_file(binary(), String.t()) :: {:ok, String.t()} | {:error, any()}
  @callback url(String.t()) :: String.t()
  @callback list_path(String.t()) ::
              {:ok, [%{name: String.t(), path: String.t(), type: :file | :directory}]}
              | {:error, any()}
  @callback move(String.t(), String.t()) :: :ok | {:error, any()}

  def put_file(binary, path), do: impl().put_file(binary, path)
  def url(path), do: impl().url(path)
  def list_path(path), do: impl().list_path(path || "")
  def move(from, to), do: impl().move(from, to)

  defp impl, do: Application.get_env(:marbles, :storage_adapter)
end
