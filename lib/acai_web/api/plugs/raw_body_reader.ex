defmodule AcaiWeb.Api.Plugs.RawBodyReader do
  @moduledoc """
  Captures the raw request body while Plug.Parsers reads it.

  See core.OPERATIONS.1.
  """

  import Plug.Conn

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:more, chunk, conn} ->
        {:more, chunk, append_chunk(conn, chunk)}

      {:ok, chunk, conn} ->
        # core.OPERATIONS.1
        {:ok, chunk, capture_body(conn, chunk)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_chunk(conn, chunk) do
    chunks = Map.get(conn.private, :api_raw_body_chunks, [])
    put_private(conn, :api_raw_body_chunks, [chunk | chunks])
  end

  defp capture_body(conn, chunk) do
    chunks = [chunk | Map.get(conn.private, :api_raw_body_chunks, [])]

    conn
    |> put_private(:api_raw_body_chunks, nil)
    |> assign(:raw_body, chunks |> Enum.reverse() |> IO.iodata_to_binary())
  end
end
