An attempt at implementing Conal Elliot's FRP in Koka.

The core idea of Conal Elliot's FRP is that time is _continuous_. As I only have experience with "FRP-ish" systems which model time as discrete streams, I want to explore how the real thing works. Ideally, I would like to be able to implement a full end-to-end interactive application using the system.

I also want to explore [Koka](https://koka-lang.github.io/), an extremely interesting functional programming language. Koka's defining feature is effect types/handlers, which is a beautiful, extremely general abstraction. It may be possible to express some notion of FRP using effects, but I am unsure how this would look.

Koka also strives for generality and simplicity in all other design aspects, which is philosophically very aligned with the goals of FRP.

Sources:

- [Conal Elliot - Essence and origins of FRP](https://github.com/conal/talk-2015-essence-and-origins-of-frp)
- [Push-pull functional reactive programming](http://conal.net/papers/push-pull-frp/)
- [Functional Reactive Programming - Haskell wiki](https://wiki.haskell.org/Functional_Reactive_Programming)

Conal Elliot's papers/talks use "semantic functions" to define the, named either _μ_ (for "meaning") or `at`.
