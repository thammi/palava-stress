WebSocket = require('ws')
Promise = require('bluebird')
Combinatorics = require('js-combinatorics')
extend = require('extend')
sys = require('sys')
range = require('array-range')

chai = require("chai")
chaiAsPromised = require("chai-as-promised")

chai.use(chaiAsPromised)
chai.should()

class Benchmark
  constructor: () ->
    @types = {}

  benchmark: (id, fun) ->
    type = @types[id]

    if not type?
      type = @types[id] = {count: 0, sum: 0, max: 0}

    start = Date.now()

    return fun().then (id) =>
      duration = Date.now() - start

      type.sum++
      type.count += duration
      type.max = Math.max(type.max, duration)

      return

    .catch (err) ->
      console.log(err.stack)
      process.exit(1)

bench = new Benchmark()

test_run = (target, room) ->
  env = {}

  ids = {}

  send = (id, data) ->
    env[id].send(JSON.stringify(data))

  receive = (id) ->
    return new Promise (resolve, reject) ->
      env[id].once 'message', (data, flags) ->
        resolve(JSON.parse(data))

  tests = [
    # connect all
    () ->
      return Promise.all ['a', 'b', 'c'].map (name) ->
        return bench.benchmark 'connect', () ->
          new Promise (resolve, reject) ->
            ws = new WebSocket(target)
            ws.once('open', resolve)
            ws.once('error', reject)
            env[name] = ws

    # join a
    () ->
      status = {
        a: 1
      }

      send('a', {
        event: 'join_room'
        room_id: room
        status: status
      })

      return receive('a').then (answer) ->
        ids.a = answer.own_id
        answer.event.should.equal('joined_room')
        answer.peers.should.be.empty

    # join b
    () ->
      status = {
        b: 1
      }

      send('b', {
        event: 'join_room'
        room_id: room
        status: status
      })

      return Promise.all([
        receive('b').then (answer) ->
          ids.b = answer.own_id
          answer.event.should.equal('joined_room')
        receive('a').then (answer) ->
          answer.event.should.equal('new_peer')
          answer.status.should.deep.equal(status)
      ])

    # join c
    () ->
      status = {
        c: 1
      }

      send('c', {
        event: 'join_room'
        room_id: room
        status: status
      })

      return Promise.all([
        receive('c').then (answer) ->
          ids.c = answer.own_id
          answer.event.should.equal('joined_room')
        receive('a').then (answer) ->
          answer.event.should.equal('new_peer')
          answer.status.should.deep.equal(status)
        receive('b').then (answer) ->
          answer.event.should.equal('new_peer')
          answer.status.should.deep.equal(status)
      ])

    # status a
    () ->
      new_status = {
        test: 42
        blub: 'i am a test string!'
      }

      send('a', {
        event: 'update_status'
        status: new_status
      })

      response = {
        event: 'peer_updated_status'
        sender_id: ids.a
        status: new_status
      }

      return Promise.all([
        receive('b').should.eventually.deep.equal(response)
        receive('c').should.eventually.deep.equal(response)
      ])

    # send stuff
    () ->
      pairs = [['a', 'b'], ['b', 'c'], ['a', 'c']]

      send_test = (from, to, count) ->
        msg = {
          event: 'offer'
          sdp: 'bla blub'
        }

        send(from, {
          event: 'send_to_peer'
          peer_id: ids[to]
          data: msg
        })

        response = extend({sender_id: ids[from]}, msg)

        receive(to).should.eventually.deep.equal(response).then () ->
          if count > 1
            return send_test(to, from, count - 1)
          else
            return


      return Promise.mapSeries pairs, ([from, to]) ->
        return send_test(from, to, 30)

    # closing
    () ->
      env.a.close()
      env.b.close()
      env.c.close()

      return Promise.resolve()
  ]

  return Promise.mapSeries tests, (test) ->
    return test()

run = (num) ->
  return test_run(process.argv[2], 'test_'+num)

Promise.map(range(500), run, {concurrency: 10}).then () ->
  for id, entry of bench.types
    console.log(id, entry)
.catch (err) ->
  console.log(err)

