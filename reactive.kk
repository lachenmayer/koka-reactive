import std/num/float64

alias time = float64
struct behavior<a>
  at: time -> a

fun identity<a>(x: a): a
  x

val time: behavior<time> = Behavior(at = identity)

fun test-time()
  assert("time is identity", at(time)(5.0) == 5.0)

fun lift0<a>(constant: a): behavior<a>
  Behavior(at = fn(_) constant)

fun lift1<a, b>(f: a -> b, a: behavior<a>): behavior<b>
  Behavior(at = fn(t) f(a.at()(t)))

fun lift2<a, b, c>(f: (a, b) -> c, a: behavior<a>, b: behavior<b>): behavior<c>
  Behavior(at = fn(t) f(a.at()(t), b.at()(t)))

fun test-lifts()
  assert("lift0", "yes".lift0.at()(5.0) == "yes")
  fun double(x)
    x * 2.0
  assert("lift1", double.lift1(time).at()(5.0) == 10.0)
  assert("lift2", float64/(*).lift2(time, 2.0.lift0).at()(5.0) == 10.0)
