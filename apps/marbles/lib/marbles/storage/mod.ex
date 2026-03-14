defmodule Marbles.Storage do
  @callback put_file(binary(), String.t()) :: {:ok, String.t()} | {:error, any()}
  @callback url(String.t()) :: String.t()

  def put_file(binary, filename), do: impl().put_file(binary, filename)
  def url(filename), do: impl().url(filename)

  defp impl, do: Application.get_env(:marbles, :storage_adapter)
end
