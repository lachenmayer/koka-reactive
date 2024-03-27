import std/num/float64

alias time = float64
struct behavior<a>
  at: time -> a

fun identity<a>(x: a): a
  x

val time: behavior<time> = Behavior(at = identity)

fun main()
  val t = at(time)(5.0)
  println(t.show)
