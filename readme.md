This is an attempt at implementing Conal Elliott's _functional reactive programming_ (FRP) paradigm in [Koka](https://koka-lang.github.io/).

I am writing this as an experience report / "lab notebook" as I implement this, to document any learnings as well as any issues/roadblocks I encounter along the way.

A lot of the writing about functional programming only focuses on the ideas and theory, and leaves out all of the bits in between. My goal is to document the entire thought process, as well as all of the inscrutable errors and broken/incomplete tooling we'll be sure to encounter along the way.

**This is very much a work in progress.** It's unclear if this project will ever result in runnable software, but you might get some interesting insights about FRP, Koka, and what computer science research/experimentation actually looks like in practice.

**Buzzword bingo:** _cross-platform reactive UI framework in functional research language with algebraic effects_

# 2024-03-27

## Goals

FRP is an elegant system for describing time-varying computations using the concepts of _behaviors_ and _events_. Behaviors represent _continuous_ time-varying values, while events describe _discrete_ streams of values, with associated times.

As I only have experience with "FRP-ish" systems which model time as discrete streams, I want to explore the implications of continuous time.

I also want to explore [Koka](https://koka-lang.github.io/), an extremely interesting functional programming language. Koka's defining feature is algebraic effect types/handlers, which is a beautiful, extremely general abstraction. It may be possible to express FRP using effects somehow, but I am unsure how this would look.

Koka also strives to be ["minimal but general"](https://koka-lang.github.io/koka/doc/book.html#why-mingen) in all other design aspects, which is philosophically very aligned with the goals of FRP.

Ideally, I would like to be able to implement a full end-to-end interactive application using the system. Since Koka is designed to be easily embeddable and can compile to JavaScript and WebAssembly, it should be possible to implement a web renderer.

Another fun experiment would be to try to write a reactive UI layer in Koka on top of some kind of Rust graphics library, eg. something like [egui](https://github.com/emilk/egui).

As I'm currently making a living building an [iOS app](https://apps.apple.com/gb/app/picnic-photos/id6450713784), another interesting goal could be to implement a Koka UI layer which calls into UIKit (similar to SwiftUI or React Native). Using Xcode any longer than necessary is not exactly my idea of fun though, so this is maybe a bit less likely to happen...

## WTF is FRP

I am watching/reading the following:

- [Conal Elliott - Essence and origins of FRP](https://github.com/conal/talk-2015-essence-and-origins-of-frp)
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

Conal Elliott's papers/talks use "semantic functions" to define the, named _μ_ (for "meaning") or `at`/`occ` for behaviors/events respectively.

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

At a brief flick through, the paper doesn't feel very convincing: the "reactor" example doesn't do anything a normal function couldn't do, and the actors are not much more than what `Subject`s in RxJS do. Perhaps I've been listening to Conal Elliott too much today, but the abstractions feel limiting and ad-hoc.

[_On the coexistence of reactive code and imperative code in distributed applications_](https://web.archive.org/web/20230509150202/https://cris.vub.be/ws/portalfiles/portal/86362735/Sam_Van_den_Vonder_PhD_thesis.pdf) also looks interesting.

## Events & Reactivity

Let's get back to implementing classic FRP from _Functional Reactive Animation_.

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

The next part of the _Functional Reactive Animation_ (section 2.3) implements the various event transformation operators, using various types of arrows.

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

Straightforward enough.

The paper has a `constEv` operator for constant events -- this is unnecessary in our implementation because we can just use the `Event((time, value))` constructor.

# 2024-03-28

## External events & behaviors

The next section mentions external events. The paper only considers mouse presses: `lbp`, `rbp` for **l**eft and **r**ight **b**utton **p**ress respectively.

The type signature is quite interesting: `Time -> Event (Event ())`.

When called with some time `t0`, `lbp(t0)` returns an event which in turn yields _another_ event. This event represents the mouse button being lifted.

Implementing external events definitely adds quite a bit of complexity at this point -- I'm not sure if we have enough of the puzzle in place to warrant exploring this.

On the other hand, it is far more interesting to have something actually interactive to play with.

Also, I really want to figure out how the space-time leaks, trimming, etc. actually play out in practice.

Reading a bit further: "Certain external phenomena can be treated as behaviors, too. For example, the position of the mouse can naturally be thought of as a vector behavior."

The example of following the mouse using a spring is extremely nice, a true "functional pearl".

Searching the [Koka source](https://github.com/koka-lang/koka) for "mouse" reveals that Koka actually has a comprehensive DOM model.

The fastest way to get to some real events would probably be to call DOM methods directly from Koka. This does mean we need to compile to JS and run this inside a browser.

In an ideal world, I would like to specify a generic "system interface" which would make the Koka programs backend-independent, similar to React Native's native interface. Each backend would then need to implement certain `extern import`s.

Definitely worth exploring how easy it is to run Koka in a browser for now.

## Digression: `std/time`

Checking out the library docs on the website, I come across the [`std/time`](https://koka-lang.github.io/koka/doc/std_time.html) module. This has some really interesting implementations of timestamps, instants, time math etc.

Perhaps we should be using this as the `time` type?

Interestingly, timestamps are implemented as [`ddouble`](https://koka-lang.github.io/koka/doc/std_num_ddouble.html#type_space_ddouble), ie. 128-bit floating point numbers. This seems... overkill?

Considering that one of the submodules is `std/time/astro`, I assume this was implemented for some kind of scientific time measurement usecase.

Looking at the implementation of [`now()`](https://github.com/koka-lang/koka/blob/6da642999f7847a4d77076e6b99d141df0e17913/lib/std/time/chrono.kk#L53-L57), obviously all of the existing backends use (64-bit) Unix timestamps which need to be converted into `ddouble`s.

> Instants use the mighty 128-bit ddouble timestamps to represent a duration since the epoch. This gives very high range and precision (up 31 decimal digits). It spans about 10^300 years into the past and future, well beyond the expected life span of the universe. Any time can be expressed with atto-second (10^-18) precision up to about 300,000 years in the past and future, and with pico-second (10^-12) precision any time since the age of the universe (about 13.8 billion years ago) up to 30 billion years into the future. For durations under 300 years, the precision is in excess of a zepto second (10^-21). For comparison, it takes light about 500 zepto-seconds to travel the length of an hydrogen atom.

Incredibly over-engineered. This should not be in the std lib, at least not as `std/time`. Maybe `std/time/high-precision` or something like that...

Anyway.

## Running Koka in the browser

Looking at the compiler help prompt, we can use `koka --target=js` to output JS. There's also a `jsweb` target, this might actually be the one we want.

We start with a simple hello world file `web.kk`:

```koka
fun main()
  println("hello web")
```

Using `koka --target=js --execute web.kk`, we get some compiler output followed by `hello web`!

That's pretty nice, this probably runs using Node.

Let's try the same with the `jsweb` target (`koka --target=jsweb --execute web.kk`):

```
...more compiler output here...
linking : web/@main
created : .koka/v3.1.1/js-debug-67a439/index.html
/bin/sh: .koka/v3.1.1/js-debug-67a439/index.html: Permission denied
```

Shame!

Looking at the created directory, we can see our main entrypoint in `web__main.mjs`:

```js
// Koka generated module: web/@main, koka version: 3.1.1
"use strict"

// imports
import * as $std_core_types from "./std_core_types.mjs"
import * as $std_core_hnd from "./std_core_hnd.mjs"
import * as $std_core_exn from "./std_core_exn.mjs"
import * as $std_core_bool from "./std_core_bool.mjs"
import * as $std_core_order from "./std_core_order.mjs"
import * as $std_core_char from "./std_core_char.mjs"
import * as $std_core_int from "./std_core_int.mjs"
import * as $std_core_vector from "./std_core_vector.mjs"
import * as $std_core_string from "./std_core_string.mjs"
import * as $std_core_sslice from "./std_core_sslice.mjs"
import * as $std_core_list from "./std_core_list.mjs"
import * as $std_core_maybe from "./std_core_maybe.mjs"
import * as $std_core_either from "./std_core_either.mjs"
import * as $std_core_tuple from "./std_core_tuple.mjs"
import * as $std_core_show from "./std_core_show.mjs"
import * as $std_core_debug from "./std_core_debug.mjs"
import * as $std_core_delayed from "./std_core_delayed.mjs"
import * as $std_core_console from "./std_core_console.mjs"
import * as $std_core from "./std_core.mjs"
import * as $web from "./web.mjs"

// externals

// type declarations

// declarations

export function _expr() /* () -> console/console () */ {
  return $std_core_console.printsln("hello web")
}

export function _main() /* () -> <st<global>,console/console,div,fsys,ndet,net,ui> () */ {
  return $std_core_console.printsln("hello web")
}

// main entry:
_main($std_core.id)
```

(Prettier in VS Code prettified this for me, the formatting is not exactly as is...)

First thoughts: there are a lot of imports here. Most of these aren't used (as VS Code tells me). This could probably be tree-shaken further. I wonder if this is the entire stdlib, or genuinely only the parts that are needed for `println`.

Anyway, surprisingly nice output, even when looking at some of the included core lib files.

I am not sure what the `_expr` export is for.

Surprisingly, there is another file `web.mjs`, which has an export called `main`. This looks ideal for importing into larger JS apps.

I wonder why the code is duplicated in `web__main.mjs`, rather than just calling the "actual" main.

The `index.html` is trivial.

Obviously, simply opening the `index.html` in a browser doesn't work, because module imports don't work locally...

```
Access to script at 'file:///Users/harry/Code/koka-reactive/.koka/v3.1.1/js-debug-67a439/web__main.mjs' from origin 'null' has been blocked by CORS policy: Cross origin requests are only supported for protocol schemes: http, isolated-app, arc, https, chrome-untrusted, data, chrome-extension, chrome.
```

Truly annoying, but what can you do. Definitely not the first (or last...) time I've seen this error, a quick `npx http-server .koka/v3.1.1/js-debug-67a439` gets us a lovely artisanal local web server.

I'm pleasantly surprised: we see `hello web` on the page itself, rather than just as console output. This is really nice for getting started, I can see the first-use experience being quite nice once some of the kinks are ironed out.

I want to debug the "Permission denied" error above, if this worked out of the box this would be _such_ a nice experience, even for beginners.

I search the Koka codebase for "jsweb", and find some interesting files.

I want to jump to definition in the Haskell files though, but I don't have a proper Haskell dev environment set up.

I download the VS Code Haskell extension, but it tells me I need [GHCup](https://www.haskell.org/ghcup/). OK, happy to install that. Good to know that the Haskell world has at least made some progress on usability in the last decade (ie. since I [last used Haskell in anger](https://github.com/lachenmayer/arrowsmith) - the installation instructions are a blast from the past...).

Quick `curl | sh` job to install, the script asks a bunch of questions and has useful help links. This is truly so much better than setting up all of this manually, thanks to the Rust community for setting the standard for how a programming environment should be installed.

Also amazing that it ends with this line: "If you are new to Haskell, check out https://www.haskell.org/ghcup/steps/". Extremely nice.

I reopen the Koka project, and I get a toast stating "Working out the project GHC version. This might take a while...". It does indeed take a while, ain't nobody got time for that.

The `codeGen` function in `CodeGen.hs` writes the `created : .koka/v3.1.1/js-debug-67a439/index.html` line, so in theory we only need to find where this is called and see what happens next.

I tried looking up what the `--execute` flag actually sets, it seems to be setting a field called `evaluate`?

Call tree: `codeGen` <- `moduleCodegen` <- `moduleCompile` <- `modulesBuild` <- `modulesFullBuild` -- this is unused? 🤔

Anyway, time to park this. Finding the GHC version still hasn't completed, so close but no cigar Haskell...

## Koka DOM

Back to the task at hand: trying to use the Koka DOM library so we can get some real IO events into our lovely new FRP system.

Importing `std/sys/dom` does not work, hmm!

Looking at the repo more closely, the DOM code is in `lib/v1/std/sys/dom`. This might mean that this is code that doesn't even run on the current version of Koka (v3), hmmmmm.

Ok, experiment failed.

# 2024-03-29

## Arbitrary time is a problem: towards pull-based FRP (eg. Yampa)

Some further thinking in the proverbial hammock. With arbitrary time as input, the issue of matching exact times to behavior values is really very serious.

Let's say we have an input device (eg. touch screen / mouse) that samples at a frame rate `I` Hz, and we want to output frames at `O` Hz (frames per second).

In general, we can assume that `I != O`, and it is more likely that `I > O`, if we're dealing with raw hardware events.

To be able to accurately consider the input as a behavior, we need some way of interpolating between values, ie. resampling. This means we need to know what the sample rate is.

Even if we don't want to interpolate, ie. just getting the latest event is accurate enough for our purposes, we still need to know the time frame for which a single event is valid. At each time `t`, each input event is valid in the interval `(t, t + 1/I)` seconds.

The trimming problem rears its head again: even if we don't want to allow access to past events, we need to persist input events for at least `1/I` seconds.

The FRP model doesn't state what happens when you ask for an event in the past: should it just return the oldest event we have stored? Surely this breaks integration.

More philosophically, arbitrary access to the past is physically impossible, unless you have infinite memory.

[_Garbage collecting the semantics of FRP_](http://conal.net/blog/posts/garbage-collecting-the-semantics-of-frp) asks:

> I suspect the whole event model can be replaced by integration. Integration is the main remaining piece.
>
> How weak a semantic model can let us define integration?

Definitely an interesting thought.

What if we make `t` relative, ie. `t = 0` is always "now"? Then values at `t > 0` can be interpreted as scheduled/future values ("timeout in 30s", "show this notification at 8pm", etc.), and `t < 0` as past values. We could then add bounds to some behaviors, ie. certain behaviors (I would suspect most of them) would not support accessing past values.

Getting a value `at(t)` where `t > 0` feels like it is always equivalent to waiting for some timeout `t`, and then fetching `at(0)`.

Is it worth elevating this to a fundamental part of the model? I suspect not. If we get rid of time altogether, we're left with a single `poll: () -> a`. I would imagine many behaviors to return a value similar to Rust futures' [`Poll`](https://doc.rust-lang.org/std/task/enum.Poll.html) (`Poll a = Ready a | Pending`).

How can we recover integration and differentiation from this? We could `poll` at a fixed rate, and just linearly interpolate between points. Then the differential is just the slope, and we can approximate the integral using the [trapezoidal rule](https://en.wikipedia.org/wiki/Trapezoidal_rule).

This is the "pull" part of push-pull FRP. What about push?

An interesting post here about time leaks in arrowized FRP: https://web.archive.org/web/20140820094516/http://blog.edwardamsden.com/2011/03/demonstrating-time-leak-in-arrowized.html

Again, integration is the culprit: it depends on all past values. The output is only required after 30 seconds, so this builds up an extremely long sequence of thunks.

Watching [Paul Hudak - Euterpea: From signals to symphonies](https://www.youtube.com/watch?v=xtmo6Bmfahc): a beautiful system for music. In music, modelling the time parameter explicitly absolutely makes sense. All the values you need have clear bounds: in music, we are only really interested in audible frequencies, which gives us obvious parameters for sampling rates (via Shannon-Nyquist etc.).

The [physical model of a flute](https://youtu.be/xtmo6Bmfahc?t=2866) is extremely cool.

Reading about Yampa's [reactimate](https://wiki.haskell.org/Yampa/reactimate), this seems like exactly the polling/sampling loop I imagined.

For music / motion graphics / animation etc. where it's possible to fully control time, this does seem like an incredibly powerful paradigm. Arrowized Ableton? Arrowized After Effects?

## Other FRP models

[Sodium](https://github.com/SodiumFRP/sodium) looks interesting, worth exploring further. Very "functional programming" approach to docs: no useful information in the readme, the only website is the user forums.

Some really interesting discussions on that forum at first glance, eg. [Preventing space leaks](http://sodium.nz/t/preventing-space-leaks/314).

[Hareactive](https://github.com/funkia/hareactive) looks very cool. The concepts of _behavior_, _stream_, _future_ are a great distillation of the concepts. ([rsocket-js](https://rsocket.io/guides/rsocket-js/) calls futures "singles", which is possibly even clearer.)

The concept of [`Now`](https://github.com/funkia/hareactive?tab=readme-ov-file#now) is interesting, though I am not sure I understand it fully yet.

[Turbine](https://github.com/funkia/turbine) is a frontend framework built on top of Hareactive.

[Funkia](https://github.com/funkia) as a whole seems like a really interesting org: pure functional programming for TypeScript.

[Simon Friis Vindum (@paldepind)](https://github.com/paldepind) seems to be behind all of this. He also created [flyd](https://github.com/paldepind/flyd).

## Hareactive

Hareactive is definitely worth a closer look.

Very interestingly, its "time" seems to be an abstract tick, rather than "real" time: https://github.com/funkia/hareactive/blob/92f2fad1ff8a715a75fe8013f7f9585ceab7ce06/src/clock.ts

This makes sense, it has [`time: Behavior<Time>`](https://github.com/funkia/hareactive/blob/92f2fad1ff8a715a75fe8013f7f9585ceab7ce06/src/time.ts#L70) which calls `Date.now()` using [`fromFunction`](https://github.com/funkia/hareactive/blob/92f2fad1ff8a715a75fe8013f7f9585ceab7ce06/src/behavior.ts#L421).

It seems to support [push & pull](https://github.com/funkia/hareactive/blob/92f2fad1ff8a715a75fe8013f7f9585ceab7ce06/src/common.ts#L18-L23).

One thing that seems strange is that parents & children seem to be linked both ways, most likely so that behaviors can push & pull both ways. I don't think Koka's semantics even allow representing this (perhaps with refs?), so I don't think this approach can really work.

The implementation is very imperative overall, this can hopefully be made more functional.

The `Now` monad seems like something that could be implemented using effect handlers. `runNow` is clearly an effect.

**To be continued...**
