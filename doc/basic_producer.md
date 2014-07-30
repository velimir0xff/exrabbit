Basic Producer API
==================

## Confirm mode

Switching a channel into confirm-mode makes the broker report back to the
client upon successful enqueueing of a message or in some other cases (FIXME:
list them).

```elixir
Exrabbit.Channel.set_mode(chan, :confirm)

# awaiting for a single message to be confirmed
Producer.publish(producer, "hi", await_confirm: true, timeout: 100)

# batch awaiting
Producer.publish(producer, "1")
Producer.publish(producer, "2")
Producer.publish(producer, "3")
:ok = Exrabbit.Channel.await_confirms(chan, 100)
```


## Tx mode

In the tx-mode, messages have to be committed for the broker to accept them
before routing them to exchanges.

```elixir
Exrabbit.Channel.set_mode(chan, :confirm)
# committing a single message; implicitly starts a new transaction
Producer.publish(producer, "hi")
:ok = Exrabbit.Channel.commit(chan)

# committing multiple messages to be processed in a single transaction
Producer.publish(producer, "1")
Producer.publish(producer, "2")
Producer.publish(producer, "3")
:ok = Exrabbit.Channel.commit(chan)
```
