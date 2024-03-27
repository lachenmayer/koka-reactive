import std/num/float64

alias time = float64

struct behavior<a>
  at: time -> a

struct event<a>
  occur: (time, a)

fun identity<a>(x: a): a
  x

val time: behavior<time> = Behavior(identity)

fun test-time()
  assert("time is identity", at(time)(5.0) == 5.0)

fun behavior/zero/lift<a>(constant: a): behavior<a>
  Behavior(fn(_) constant)

fun behavior/one/lift<a, b>(f: a -> b, a: behavior<a>): behavior<b>
  Behavior(fn(t) f(a.at()(t)))

fun behavior/two/lift<a, b, c>(f: (a, b) -> c, a: behavior<a>, b: behavior<b>): behavior<c>
  Behavior(fn(t) f(a.at()(t), b.at()(t)))

fun (+)(a: behavior<float64>, b: behavior<float64>): behavior<float64>
  (+).lift(a, b)

fun (-)(a: behavior<float64>, b: behavior<float64>): behavior<float64>
  (-).lift(a, b)

fun (*)(a: behavior<float64>, b: behavior<float64>): behavior<float64>
  (*).lift(a, b)

fun (/)(a: behavior<float64>, b: behavior<float64>): behavior<float64>
  (/).lift(a, b)

fun test-lifts()
  assert("lift0", "yes".lift.at()(5.0) == "yes")
  fun double(x)
    x * 2.0
  assert("lift1", double.lift(time).at()(5.0) == 10.0)
  assert("lift2", float64/(*).lift(time, 2.0.lift).at()(5.0) == 10.0)
  assert("overload", (time * 2.0.lift).at()(5.0) == 10.0)

fun time-transform<a>(a: behavior<a>, transform: behavior<time>): behavior<a>
  Behavior(fn(t) a.at()(transform.at()(t)))

fun test-time-transform()
  assert("time-transform", time.time-transform(time * 2.0.lift).at()(4.0) == 8.0)

fun until<a>(behavior: behavior<a>, event: event<behavior<a>>): behavior<a>
  Behavior(fn(t)
    val (event-time, event-behavior) = event.occur()
    if t <= event-time then
      behavior.at()(t)
    else
      event-behavior.at()(t)
  )

fun map<a, b>(event: event<a>, f: (time, a) -> b): event<b>
  val (time, value) = event.occur()
  Event((time, f(time, value)))

fun map-time<a, b>(event: event<a>, f: time -> b): event<b>
  event.map fn(time, _) f(time)

fun map-value<a, b>(event: event<a>, f: a -> b): event<b>
  event.map fn(_, value) f(value)
