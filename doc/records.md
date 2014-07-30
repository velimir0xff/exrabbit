Working with Erlang records
===========================

Exrabbit does not wrap all possible methods provided by the Erlang client.
Instead, it gives the users access to Erlang records to support all of the
options implemented in the client.

Some of the records are superceded completely by functions in Exrabbit, for
example:

  * `queue.purge` is exposed as `Exrabbit.Channel.queue_purge`
  * `basic.publish` is used internally by `Exrabbit.Producer.publish`
  * `basic.consume` is internal to `Exrabbit.Consumer.subscribe`

In situations where making a record part of Exrabbit would just mean wrapping
it, the record is imported as is instead. Those include `queue.declare`,
`exchange.declare`, `basic.qos`, and others.

In order to use imported records, you need to `require` or `use`
`Exrabbit.Records` and replace all dots with underscores in their names:

```elixir
use Exrabbit.Records

queue = queue_declare(queue: "name", exclusive: true, auto_delete: true)
consumer = Consumer.new(queue: queue)

# ...
```

See `lib/exrabbit/records.ex` for the complete list.
