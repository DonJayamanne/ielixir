defmodule IElixir.Kernel.Session do
  alias IElixir.Kernel.History

  @moduledoc """
  This module provides genserver that handles current shell session.
  It stores current kernel encryption so is able to compute signatures.
  Also it handles current session's key.
  """

  @typedoc "Return values of `start*` functions"
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  require Logger
  use GenServer

  @doc """
  Start the session server

    IElixir.Kernel.Session.start_link(%{"signature_scheme" => "hmac-sha256", "key" => "7534565f-e742-40f3-85b4-bf4e5f35390a"})

  ## Options

  "signature_scheme" and "key" options are required for proper work of HMAC server.
  """
  @spec start_link(map) :: on_start
  def start_link(conn_info) do
    GenServer.start_link(__MODULE__, conn_info, name: __MODULE__)
  end

  def init(conn_info) do
    init_state = %{
      session_id: History.get_session(),
      execution_count: 0
    }

    case String.split(conn_info["signature_scheme"], "-") do
      ["hmac", tail] ->
        {:ok,
         Map.merge(init_state, %{
           signature_data: {String.to_atom(tail), conn_info["key"]}
         })}

      ["", _] ->
        {:ok,
         Map.merge(init_state, %{
           signature_data: {nil, ""}
         })}

      scheme ->
        Logger.error("Invalid signature_scheme: #{inspect(scheme)}")
        {:error, "Invalid signature_scheme"}
    end
  end

  @doc """
  Compute signature for provided message.
  Each argument must be valid UTF-8 string, because it is JSON decodable.

  ### Example

      iex> IElixir.HMAC.compute_signature("", "", "", "")
      "25eb8ea448d87f384f43c96960600c2ce1e713a364739674a6801585ae627958"

  """
  @spec compute_signature(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def compute_signature(header_raw, parent_header_raw, metadata_raw, content_raw) do
    GenServer.call(
      __MODULE__,
      {:compute_sig, [header_raw, parent_header_raw, metadata_raw, content_raw]}
    )
  end

  @spec get_session :: String.t()
  def get_session() do
    GenServer.call(__MODULE__, :get_session)
  end

  @spec increase_counter :: :ok
  def increase_counter() do
    GenServer.cast(__MODULE__, :increase_counter)
  end

  @spec get_counter :: Integer.t()
  def get_counter() do
    GenServer.call(__MODULE__, :get_counter)
  end

  def handle_call(:get_session, _from, %{session_id: session} = state) do
    {:reply, session, state}
  end

  def handle_call(:get_counter, _from, %{execution_count: execution_count} = state) do
    {:reply, execution_count, state}
  end

  def handle_call({:compute_sig, _parts}, _from, %{signature_data: {_, ""}} = state) do
    {:reply, "", state}
  end

  def handle_call({:compute_sig, parts}, _from, %{signature_data: {algo, key}} = state) do
    {:reply, IElixir.Util.Crypto.compute_signature(algo, key, parts), state}
  end

  def handle_cast(:increase_counter, state) do
    {:noreply, Map.update(state, :execution_count, 0, &(&1 + 1))}
  end
end
