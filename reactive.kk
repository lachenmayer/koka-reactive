import std/num/float64

alias time = float64
struct behavior<a>
  at: time -> a
struct event<a>
  occur: (time, a)

fun identity<a>(x: a): a
  x

val time: behavior<time> = Behavior(at = identity)

fun test-time()
  assert("time is identity", at(time)(5.0) == 5.0)

fun behavior/zero/lift<a>(constant: a): behavior<a>
  Behavior(at = fn(_) constant)

fun behavior/one/lift<a, b>(f: a -> b, a: behavior<a>): behavior<b>
  Behavior(at = fn(t) f(a.at()(t)))

fun behavior/two/lift<a, b, c>(f: (a, b) -> c, a: behavior<a>, b: behavior<b>): behavior<c>
  Behavior(at = fn(t) f(a.at()(t), b.at()(t)))

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
  Behavior(at = fn(t) a.at()(transform.at()(t)))

fun test-time-transform()
  assert("time-transform", time.time-transform(time * 2.0.lift).at()(4.0) == 8.0)

fun until<a>(behavior: behavior<a>, event: event<behavior<a>>): behavior<a>
  Behavior(at = fn(t)
    val (event-time, event-behavior) = event.occur()
    if t <= event-time then
      behavior.at()(t)
    else
      event-behavior.at()(t)
  )