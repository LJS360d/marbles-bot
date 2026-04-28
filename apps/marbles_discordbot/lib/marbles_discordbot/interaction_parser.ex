defmodule MarblesDiscordbot.InteractionParser do
  @moduledoc false

  @spec parse_collection_page_sort(String.t()) ::
          {:ok, %{page: pos_integer(), sort_key: String.t()}} | :error
  def parse_collection_page_sort(payload) when is_binary(payload) do
    with [page_str, sort_str] <- String.split(payload, "_", parts: 2),
         {page, ""} when page > 0 <- Integer.parse(page_str) do
      {:ok, %{page: page, sort_key: String.trim_leading(sort_str, ":")}}
    else
      _ -> :error
    end
  end

  @spec parse_pack_page_session(String.t(), String.t()) :: {non_neg_integer(), String.t()}
  def parse_pack_page_session(payload, default_session_id)
      when is_binary(payload) and is_binary(default_session_id) do
    case String.split(payload, "_", parts: 2) do
      [page_str, session_id] ->
        case Integer.parse(page_str) do
          {page, ""} when page >= 0 -> {page, session_id}
          _ -> {0, default_session_id}
        end

      [page_str] ->
        case Integer.parse(page_str) do
          {page, ""} when page >= 0 -> {page, default_session_id}
          _ -> {0, default_session_id}
        end
    end
  end
end
