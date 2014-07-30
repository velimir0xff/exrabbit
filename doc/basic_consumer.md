Basic Consumer API
==================

## Consumer acknowledgements

```elixir
subscription_fun = fn
  {:msg, tag, message} ->
    IO.inspect message
    Exrabbit.Channel.ack(chan, tag)
  _ -> nil
end

# specify that we will acknowledge received messages
method = basic_consume(no_ack: false)

consumer =
  Consumer.new(chan, exchange: exchange, queue: queue)
  |> Consumer.subscribe(subscription_fun, method: method)
```

