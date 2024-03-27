# koka-reactive

This is an attempt at implementing Conal Elliot's _functional reactive programming_ (FRP) paradigm in [Koka](https://koka-lang.github.io/).

FRP is an elegant system for describing time-varying computations using the concepts of _behaviors_ and _events_. Behaviors represent _continuous_ time-varying values, while events describe _discrete_ streams of values, with associated times.

As I only have experience with "FRP-ish" systems which model time as discrete streams, I want to explore the implications of continuous time.

I also want to explore [Koka](https://koka-lang.github.io/), an extremely interesting functional programming language. Koka's defining feature is effect types/handlers, which is a beautiful, extremely general abstraction. It may be possible to express FRP using effects somehow, but I am unsure how this would look.

Koka also strives to be ["minimal but general"](https://koka-lang.github.io/koka/doc/book.html#why-mingen) in all other design aspects, which is philosophically very aligned with the goals of FRP.

Ideally, I would like to be able to implement a full end-to-end interactive application using the system. Since Koka is designed to be easily embeddable and can compile to WebAssembly, it should be possible to implement a web renderer.

Another fun experiment would be to try to write a reactive UI layer in Koka on top of some kind of Rust graphics library, eg. something like [egui](https://github.com/emilk/egui).

As I'm currently making a living building an [iOS app](https://apps.apple.com/gb/app/picnic-photos/id6450713784), another interesting goal could be to implement a Koka UI layer which calls into UIKit (similar to SwiftUI or React Native). Using Xcode any longer than necessary is not exactly my idea of fun though, so this is maybe a bit less likely to happen...

I am writing this as an experience report while I implement this, to document any insights as well as issues/roadblocks I encounter along the way.

## WTF is FRP

I watched and/or read (parts of) the following:

- [Conal Elliot - Essence and origins of FRP](https://github.com/conal/talk-2015-essence-and-origins-of-frp)
- [Push-pull functional reactive programming](http://conal.net/papers/push-pull-frp/)
- [Functional Reactive Animation](http://conal.net/papers/icfp97/icfp97.pdf)
- [Functional Reactive Programming - Haskell wiki](https://wiki.haskell.org/Functional_Reactive_Programming)

In _essence and origins of FRP_, `Behavior a` is a function `Time -> a`, `Event a` is a list of event occurrences `[(Time, a)]`, where times are in ascending order (ie. oldest to newest).

The first question mark is the type of `Event` -- I feel like this relies on Haskell's lazy evaluation / infinite lists, where "getting a new event" is just blocking on evaluating the next element of a list. Since Koka is strict, how can we express this?

_Functional Reactive Animation_ represents events using a function `occ: Event a -> (Time, a)`. This seems more amenable to implementation in a strict language.

For events, I'm most interested in how we can express IO events, ie. mouse movement, screen taps, keyboard inputs, etc., which would come from the underlying system. It feels like getting an event from the system would involve blocking on `occ` for some `IOEvent`, where `occ` is implemented as a native function (`extern import` in Koka).

For a render loop, I would imagine that we emit some kind of `FrameEvent [IOEvent]` every tick (eg. 60 times a second). Concretely, we would then have a steadily incrementing `(Time, [IOEvent])` value which can then kick off all other reactivity.

The later FRP papers implement the behavior/event combinators in terms of functor/monoid/monad instances, which is obviously an extremely powerful approach. I'd like to focus on the FRP idea itself instead of implementing the whole [Typeclassopedia](https://wiki.haskell.org/Typeclassopedia), so I'm going to use the "custom" combinators (eg. the ones described in _Functional Reactive Animation_) instead of the more general ones.

I'm not even sure how typeclasses would be implemented in Koka -- at first glance, it looks like it might be just function overloading?

Also some of the names of operators will need a bit of work. For example, I don't think I can use the name `.|.` (the "cock and balls" operator?? 🤔) in Koka...

## Starting the implementation: behaviors

Conal Elliot's papers/talks use "semantic functions" to define the, named _μ_ (for "meaning") or `at`/`occ` for behaviors/events respectively.

This took me a moment to understand: if I have `at: Behavior a -> (T -> a)`, how do I get a value of `Behavior a`, and what does it contain?

Reading the Haskell wiki clarified this: they define the types as `newtype`s with `at`/`occ` as fields, of course.

In Koka, we can use [`struct`](https://koka-lang.github.io/koka/doc/book.html#sec-structs), as follows:

```koka
struct behavior<a>
  at: time -> a
```

In Koka, `struct foo { ... }` is just syntax sugar for `type foo { Foo { ... } }`, ie. a union with a single constructor ([docs](https://koka-lang.github.io/koka/doc/book.html#sec-union)). Love that, it's a perfect example of the ["minimal but general"](https://koka-lang.github.io/koka/doc/book.html#why-mingen) design principle.

One thing I'm not too hot on is that the constructor for the type is then the capitalized `Foo`, especially since Koka's preferred naming convention seems to be "kebab-case". This results in frankly horrible `Capitalized-kebab-case` type constructors.

I'm also not sure about type parameters and other named types being indistinguishable, Haskell's convention (types capitalized, variables lowercase) makes a bit more sense to me, but this is a minor issue.

As an aside, implementing Prettier for Koka in Koka would be an interesting experiment (using [Strictly Pretty](https://www.researchgate.net/publication/2629249_Strictly_Pretty) as a starting point).

We want time to be real, so we'll just define it as a double (our first brush with reality...).

```koka
alias time = float64
```

To use functions like `show` for printing floats, I had to `import std/num/float64` -- this feels quite strange, because it's defined for `int`s without having to be imported. I wonder what the rationale for this is.

We can then implement the simplest behavior, `time`:

```koka
val time: behavior<time> = Behavior(at = identity)
```

(Where `identity = fn(x) x`, obviously.)

Again a bit confusing, we have a _value_ `time` and a _type_ `time`, I can see this getting out of hand...

To test this, I try the following:

```koka
fun main()
  val t = time.at(5.0)
  println(t.show)
```

This gives me a type error which is initially a bit of a headscratcher:

```
types do not match
context      :           time.at(5.0)
term         :           time
inferred type: behavior<time>
expected type: vector<_a>
```

This has a very simple explanation: Koka has ["dot selection"](https://koka-lang.github.io/koka/doc/book.html#sec-dot), where `x.f` is syntax sugar for `f(x)`, an amazing feature. `time.at(5.0)` is desugared to `at(time, 5.0)`, which obviously doesn't match.

Two possible solutions:

1. `time.at()(5.0)`
2. `at(time)(5.0)`

I'm not sure which I prefer.

Let's get into the habit of writing tests immediately:

```koka
fun test-time()
  assert("time is identity", at(time)(5.0) == 5.0)
```

Koka's VS Code integration has a neat feature where you can run functions beginning with `test...` (and `example...` & `main`).

## Lift

The next combinator is `lift`, which is used to turn constants & pure functions into corresponding behaviors.

This has different variants based on the number of arguments, `lift0`, `lift1`, `lift2` (etc.)

These are fairly straightforward to implement:

```koka
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
```

Koka's [dot selection](https://koka-lang.github.io/koka/doc/book.html#sec-dot) really shines here.

I wish we could overload the function so that we only have a single polymorphic `lift`, but that probably leads to some gnarly issues.
