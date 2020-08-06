defmodule Exchange.Adapters.InMemoryTimeSeries do
  @moduledoc """
  Documentation for a InMemoryTimeSeries adapter
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{orders: %{}, prices: %{}, trades: %{}})
  end

  def init(state) do
    message_bus().add_listener(:trade_executed)
    message_bus().add_listener(:order_queued)
    message_bus().add_listener(:order_cancelled)
    message_bus().add_listener(:order_expired)
    message_bus().add_listener(:price_broadcast)

    {:ok, state}
  end

  def handle_info({:cast_event, :trade_executed, payload}, state) do
    # Logger.info("[InMemoryTimeSeries] Processing trade: #{inspect(payload.trade)}")
    state =
      payload.trade
    |> save_trade(state)

    {:noreply, state}
  end

  def handle_info({:cast_event, :order_queued, payload}, state) do
    # Logger.info("[InMemoryTimeSeries] Processing Order: #{inspect(payload.order)}")
    state = save_order(state, payload.order)
    {:noreply, state}
  end

  def handle_info({:cast_event, :order_cancelled, payload}, state) do
    # Logger.info("[InMemoryTimeSeries] Processing Order: #{inspect(payload.order)}")
    order = payload.order
    state =
      %{order | size: 0}
    |> save_order(state)

    {:noreply, state}
  end

  def handle_info({:cast_event, :order_expired, expired_order}, state) do
    # Logger.info("[InMemoryTimeSeries] Processing Order: #{inspect(expired_order.order)}")
    order = expired_order.order
    state =
      %{order | size: 0}
      |> save_order(state)

    {:noreply, state}
  end

  def handle_info({:cast_event, :price_broadcast, price}, state) do
    # Logger.info("[InMemoryTimeSeries] Processing Price: #{inspect(price)}")
    state =
      %{ticker: price.ticker, ask_min: price.ask_min, bid_max: price.bid_max}
    |> save_price(state)

    {:noreply, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def save_price(price, state) do
    current_time = :os.system_time(:nanosecond)
    {:ok, prices} = Map.fetch(state, :prices)
    current_time_prices = case Map.fetch(prices, current_time) do
      {:ok, value} -> value
      :error -> nil
    end
    updated_time_prices = if current_time_prices do
      Qex.push(current_time_prices, price)
    else
      Qex.new([price])
    end
    update_prices = Map.put(prices, current_time, updated_time_prices)
    Map.put(state, :prices, update_prices)
  end

  def save_order(order, state) do
    current_time = :os.system_time(:nanosecond)
    {:ok, orders} = Map.fetch(state, :orders)
    current_time_orders = case Map.fetch(orders, current_time) do
      {:ok, value} -> value
      :error -> nil
    end
    updated_time_orders = if current_time_orders do
      Qex.push(current_time_orders, order)
    else
      Qex.new([order])
    end
    update_orders = Map.put(orders, current_time, updated_time_orders)
    Map.put(state, :orders, update_orders)
  end

  def save_trade(trade, state) do
    current_time = :os.system_time(:nanosecond)
    {:ok, trades} = Map.fetch(state, :trades)
    current_time_trades = case Map.fetch(trades, current_time) do
      {:ok, value} -> value
      :error -> nil
    end
    updated_time_trades = if current_time_trades do
      Qex.push(current_time_trades, trade)
    else
      Qex.new([trade])
    end
    update_trades = Map.put(trades, current_time, updated_time_trades)
    Map.put(state, :trades, update_trades)

  end




  def get_state do
    GenServer.call(__MODULE__, :state)
  end

  def message_bus do
    Application.get_env(:exchange, :message_bus_adapter)
  end

  @behaviour Exchange.TimeSeries

  def completed_trades_by_id(_ticker, _trader_id) do
    []
  end

  def get_live_orders(_ticker) do
    []
  end
end
