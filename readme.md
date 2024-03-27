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

I am watching/reading the following:

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

I'm also not sure about type parameters and other named types being indistinguishable. Haskell's convention (types capitalized, variables lowercase) makes a bit more sense to me, but this is a minor issue.

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

I wish we could overload the function so that we only have a single polymorphic `lift`. When I try to do that, I get the following error:

```
definition lift is already defined in this module, at (18, 5)
hint: use a local qualifier?
```

The mathematical operators are all overloaded as `int/(+)`, `float64/(+)` etc, so we could try calling the functions `zero/lift`, `one/lift`, `two/lift`, etc. This actually works! This is probably a slight abuse of the syntax (I would assume these to be module names), but the calling API is nice now. Perhaps this needs to be something like `behavior0`, `behavior1`, etc.

## Time transform

The `timeTransform` combinator allows us to transform time, for example slow it down, speed it up, add delays, etc. This is where the power of explicitly modelling time becomes really apparent.

For example (as shown in _Functional Reactive Animation_), slowing down time by a factor of 2 is just:

```
timeTransform b (time / 2)
```

Delaying by two seconds:

```
timeTransform b (time - 2)
```

Extremely elegant!

This relies on overloading the mathematical operators for behaviors. In Haskell, this is done by implementing the typeclass `Num` for the type. In Koka, we can just overload the corresponding functions:

```koka
fun (+)(a: behavior<float64>, b: behavior<float64>): behavior<float64>
  (+).lift(a, b)
```

I'm not sure if it's possible to do this polymorphically (ie. for all `x` where `x/(+)` is defined), for now I'll just implement these as and when they come up.

We might want to implement these for both constants and behaviors:

```koka
fun dynamic/(+)(a: behavior<float64>, b: behavior<float64>): behavior<float64>
  (+).lift(a, b)

fun constant/(+)(a: behavior<float64>, b: float64): behavior<float64>
  (+).lift(a, b.lift)
```

One annoyance of this is that this breaks unannotated operators, eg. if we have

```koka
fun double(x)
  x * 2.0
```

We get the following error:

```
identifier (*) cannot be resolved
context      :     x * 2.0
inferred type: (_371, float64) -> _
candidates   : constant/(*)
               std/num/float64/(*)
hint         : qualify the name?
```

Not ideal, for now it's probably best to define these only for behavior + behavior, and lift manually.

The implementation is relatively straightforward:

```koka
fun time-transform<a>(a: behavior<a>, transform: behavior<time>): behavior<a>
  Behavior(at = fn(t) a.at()(transform.at()(t)))

fun test-time-transform()
  assert("time-transform", time.time-transform(time * 2.0.lift).at()(4.0) == 8.0)
```

I'm not exactly sure how to interpret time transforming with a constant time, perhaps scheduling at the given time? Will need to play around with this once I have some real behaviors to run.

## Integration

One of the benefits of modelling time as a continuous value is that integration & differentiation are well-defined.

This allows for some really cool tricks, particularly when implementing animations or anything physics-based: you can easily define displacement, velocity and acceleration functions.

Approximating integrals definitely seems a bit above my paygrade, but it sounds like [fourth-order Runge-Kutta (RK4)](https://en.wikipedia.org/wiki/Runge%E2%80%93Kutta_methods) is a decent approximation -- and doesn't look too hardcore to implement.

[`Numeric.Tools.Integration`](https://hackage.haskell.org/package/numeric-tools-0.2.0.1/docs/Numeric-Tools-Integration.html) also has different approximations.

Definitely one to look at in more detail once we've drawn the rest of the owl.

## Maybe FRP actually sucks?

Reading a bit further, _Functional Reactive Animation_ Section 4.1 (p7) states that modelling behaviors as `data Behavior a = Behavior (Time -> a)` leads to a space leak. I'm not entirely sure I understand the given example.

The stated solution with interval analysis seems very complicated. Depending on how you define your events, and how you sample time, you might completely miss an event.

I'm going to keep this simple for now, and not worry about performance.

Reading further, I'm seeing some slightly worrying later blog posts:

- [_Garbage collecting the semantics of FRP_](http://conal.net/blog/posts/garbage-collecting-the-semantics-of-frp)
- [_Why classic FRP does not fit interactive behavior_](http://conal.net/blog/posts/why-classic-FRP-does-not-fit-interactive-behavior)
- [_Trimming inputs in functional reactive programming_](http://conal.net/blog/posts/trimming-inputs-in-functional-reactive-programming)
- [_Functional interactive behavior_](http://conal.net/blog/posts/functional-interactive-behavior)

When I've previously looked at it, I've never been a fan of arrowized FRP, but maybe something like it is needed. Signals having the signature `Time -> Maybe a` just feels like entirely the wrong abstraction. This also has exactly the same problem described in FRA Section 4.2 ("Detecting predicate events"): it's possible to miss events if you happen to miss sampling the exact time of a given event.

This point in _Garbage collecting the semantics of FRP_ is making me stop in my tracks a bit:

> FRP’s semantic model, `(T->a) -> (T->b)`, allows not only arbitrary (computable) transformation of input values, but also of time. The output at some time can depend on the input at any time at all, or even on the input at arbitrarily many different times. Consequently, this model allows respoding to future input, violating a principle sometimes called “causality”, which is that outputs may depend on the past or present but not the future.
>
> In a causal system, the present can reach backward to the past but not forward the future. I’m uneasy about this ability as well. Arbitrary access to the past may be much more powerful than necessary. As evidence, consult the system we call (physical) Reality. As far as I can tell, Reality operates without arbitrary access to the past or to the future, and it does a pretty good job at expressiveness.
>
> Moreover, arbitrary past access is also problematic to implement in its semantically simple generality.

The whole trimming business seems like a fairly strong point against 'classic' FRP. (I do wonder if the space-time leaks are mainly caused by laziness.)

Elm back in the day had signals without any past access, its only mechanism for maintaining state was folding over the past (`foldp`). I always found this conceptually elegant: isn't your experience of "Reality" just a fold over your past experiences too? When a new piece of information arrives, you decide what to do with it; if you discard it, it is gone.

[_Genuinely functional GUIs_](http://conal.net/papers/genuinely-functional-guis.pdf) describes _Fruit_, an arrowized FRP system, I need to read this in more detail.

I also need to read the more recent [_Reactive Programming without Functions_](https://arxiv.org/pdf/2403.02296.pdf), which describes _Haai_.

This describes _trampolines_ for holding state. This seems like a bit of a hack. Overall I'm not convinced of the idea that functions make a system "weakly reactive" -- if you're worried about the function diverging then you could just add some hard limits to execution time.

[EmFRP](https://www.psg.c.titech.ac.jp/posts/2016-03-15-CROW2016.html) looks interesting, but I unfortunately can't access the full text.

[Stella](https://arxiv.org/abs/2306.12313) sounds convincing from the abstract: "Actors and reactors enforce a strict separation of imperative and reactive code, and they can be composed via a number of composition operators that make use of data streams."

At a brief flick through, the paper doesn't feel very convincing: the "reactor" example doesn't do anything a normal function couldn't do, and the actors are not much more than what `Subject`s in RxJS do. Perhaps I've been listening to Conal Elliot too much today, but the abstractions feel limiting and ad-hoc.

[_On the coexistence of reactive code and imperative code in distributed applications_](https://web.archive.org/web/20230509150202/https://cris.vub.be/ws/portalfiles/portal/86362735/Sam_Van_den_Vonder_PhD_thesis.pdf) also looks interesting.

## Events & Reactivity

Let's get back to implemeting classic FRP from _Functional Reactive Animation_.

We define events as follows:

```koka
struct event<a>
  occur: (time, a)
```

The paper calls this `occ`, but I want to avoid unnecessary abbreviations. I'm not sure if this is the right wording, I am still not 100% clear on the semantics of events.

Implementing `until` (called `untilB` in the paper) seems straightforward:

```koka
fun until<a>(behavior: behavior<a>, event: event<behavior<a>>): behavior<a>
  Behavior(at = fn(t)
    val (event-time, event-behavior) = event.occur()
    if t <= event-time then
      behavior.at()(t)
    else
      event-behavior.at()(t)
  )
```

Though I don't know how to properly test this, as I don't really understand its use yet.

Hopefully implementing more combinators will help.

## Event handling

This part of the _Functional Reactive Animation_ (section 2.3) implements the various event transformation operators, using various types of arrows.

I want to see if it's possible to implement these by defining new infix operators. I'm not sure what the best name for these is, but I would imagine it's some kind of `map`.

I tried to find how this works in Koka, but all I could find was the [definitions](https://github.com/koka-lang/koka/blob/6da642999f7847a4d77076e6b99d141df0e17913/lib/std/core/types.kk#L27-L34) for the built-in infix operators:

```koka
pub infixr 80  (^)
pub infixl 70  (*), (%), (/), cdiv, cmod
pub infixr 60  (++)
pub infixl 60  (+), (-)
pub infixr 55  (++.)
pub infix  40  (!=), (==), (<=), (>=), (<), (>)
pub infixr 30  (&&)
pub infixr 20  (||)
```

However it seems that `infix` isn't a keyword, and neither are `infixr`/`infixl`.

So, scrap that, let's go with `map-*`:

```koka
fun map<a, b>(event: event<a>, f: (time, a) -> b): event<b>
  val (time, value) = event.occur()
  Event((time, f(time, value)))

fun map-time<a, b>(event: event<a>, f: time -> b): event<b>
  event.map fn(time, _) f(time)

fun map-value<a, b>(event: event<a>, f: a -> b): event<b>
  event.map fn(_, value) f(value)
```
