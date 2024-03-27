import std/num/float64

alias time = float64
struct behavior<a>
  at: time -> a

val time: behavior<time> = Behavior(at = fn(t) t)

fun main()
  val t: time -> time = time.at
  println(t(5.0).show)
