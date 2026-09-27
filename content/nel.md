+++
title = "Porting NonEmpty to Koka feat. Nix"
date = 2026-09-27
description = "Porting Haskell NonEmpty into Koka, then shipping it as a nix flake library so other projects can just depend on it."
+++

I found myself porting Haskell's [NonEmpty
list](https://hackage-content.haskell.org/package/base-4.22.0.0/docs/Data-List-NonEmpty.html)
into [Koka](https://koka-lang.github.io/koka/doc/index.html). I use this
project to also learn how to use nix flake as some kind of package manager
because Koka currently doesn't have any yet.

## Problem

I saw this cool Haskell library called
[opt-env-conf](https://github.com/NorfairKing/opt-env-conf) by NorfairKing and
thought I needed to port it to Koka. Koka has
[std/os/flag](https://koka-lang.github.io/koka/doc/std_os_flags.html), but I
want to use something like opt-applicative.

While porting the first file, OptEnvConf/Args.hs, I found it uses
Data.List.NonEmpty a lot. I was using normal `list<a>` but it became difficult to
keep the semantics. So I proceeded to port NonEmpty first.

Koka also doesn't have an official package manager yet. So I decided to use nix
flake so I could use this nel library in my other projects.

## Approach

First, we define the flake.nix simply as follows:

```nix
{
  description = "Non empty list library for Koka";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        koka = pkgs.koka;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ koka ];
        };
      }
    );
}
```

This creates a devShell using nixpkgs' koka so I can use its LSP.
I use Neovim with [koka.nvim](https://github.com/syaiful6/koka.nvim) by syaiful6.

### The nel library

Then we define the nonempty type as a struct:

```koka
pub struct nonempty<a>
  head : a
  tail : list<a>
```

The struct `nonempty<a>` has type parameter `a` and two fields, `head` of type
`a` and `tail` of type `list<a>`. It represents a list that has at least one
element.

With this, Koka automatically generates the constructor `con Nonempty` of type
`forall<a> (head : a, tail : list<a>) -> total nonempty<a>`, note that the
first letter is capitalized, and field selector functions `head` of type
`forall<a> (ne : nonempty<a>) -> total a` and `tail` of type `forall<a> (ne :
nonempty<a>) -> total list<a>`.

Koka also generates a `copy` function for functional record updates. The `copy`
function itself is private so you can't use it directly. You use it like so:

```koka
val old = Nonempty(1, [2, 3, 4, 5])
val new = old(head=10)               // => Nonempty(head=10, tail=[2,3,4,5])
val new' = new(tail=[])              // => Nonempty(head=10, tail=[])
```

Koka allows you to use named parameters in a function call.

Then we define the conversion between nonempty and list:

```koka
pub fun list(ne : nonempty<a>) : list<a>
  Cons(ne.head, ne.tail)

pub fun nonempty(xs : list<a>) : maybe<nonempty<a>>
  match xs
    Nil         -> Nothing
    Cons(x, xx) -> Just(Nonempty(x, xx))
```

Obviously, nonempty to list conversion always succeeds, but list to nonempty
might fail in case of `Nil`.

The convention in Koka for conversion functions is to just name them as the
target type instead of `to-type`, e.g. `_.string` instead of `_.to-string`,
`_.maybe` instead of `_.to-maybe`, `_.int32`, `_.float128`.

Then for convenience we might define some construction functions:

```koka
pub infixr 5 (<::)  // NOTE: Fixity declaration must be after module and import
                    // declarations before any other definitions.

// ...

pub fun single(x) Nonempty(x, [])

pub fun cons(x : a, ne : nonempty<a>) : nonempty<a>
  Nonempty(x, ne.list)

pub fun list/cons(x : a, xs : list<a>) : nonempty<a>
  Nonempty(x, xs)

pub fun (<::)(x : a, ne : nonempty<a>) : nonempty<a>   // ...(1)
  cons(x, ne)

pub fun list/(<::)(x : a, xs : list<a>) : nonempty<a>  // ...(2)
  cons(x, xs)

```

Koka allows function overloading so long as the definitions live in different
namespaces. That then allows for static dispatch; the compiler searches for the
correct name and type. But this system could be less ergonomic if the functions
have the same parameter types; the compiler will require you to qualify the
callsite with enough namespace paths.

The fully qualified name for e.g. `list/cons` would be `nonempty/list/cons`
from the perspective of importing modules.

The operators allow us to write things like this:

```koka
val ne1 = 1 <:: 2 <:: single(3)
//          ^(1)  ^(1)
val ne2 = 1 <:: 2 <:: [3]
//          ^(1)  ^(2)
```

We also need `append`, `concat`, and possibly `prepend`.

```koka
pub fun append(n : nonempty<a>, m : nonempty<a>) : nonempty<a>
  n(tail = n.tail ++ m.list)

pub fun (++)(n : nonempty<a>, m : nonempty<a>) : nonempty<a>
  append(n, m)

pub fun list/append(ne : nonempty<a>, xs : list<a>) : nonempty<a>
  ne(tail = ne.tail ++ xs)

pub fun list/(++)(ne : nonempty<a>, xs : list<a>) : nonempty<a>
  append(ne, xs)

pub fun list/prepend(xs : list<a>, ne : nonempty<a>) : nonempty<a>
  match xs
    Nil         -> ne
    Cons(x, xx) -> Nonempty(x, xx ++ ne.list)

pub fun concat(nes : nonempty<nonempty<a>>) : nonempty<a>
  Nonempty( head =      nes.head.head
          , tail = Cons(nes.head.tail, nes.tail.map(_.list)).concat)

pub fun list/concat(nes : list<nonempty<a>>) : list<a>
  nes.map(_.list).concat
```

Appending just means converting the second argument to a list, and then
appending it to the tail of the first argument. We also add `list/append` for
when the second argument is already a list.

Concatenation makes the head of the head be the head of the returned nonempty
list, and converts the rest into a list of lists then concatenates them.

Next we define `map` of type `forall<a, b, e> (:nonempty<a>, :(a) -> e b) -> e nonempty<b>`.

```koka
pub fun map(ne : nonempty<a>, f : a -> e b) : e nonempty<b>
  Nonempty(ne.head.f, ne.tail.map(f))
```

The `a` and `b` are normal type variables, but `e` is Koka's effect row
variable. It says that whatever effects `f` has, `map(ne, f)` also has those
effects.

Then its sibling, the `filter` function of type
`forall<a, e> (:nonempty<a>, :(a) -> e bool) -> e list<a>`.

```koka
pub fun filter(ne : nonempty<a>, pred : a -> e bool) : e list<a>
  ne.list.filter(pred)
```

The return value is a list because it is possible that pred picks nothing.
The implementation just delegates to `list/filter`, which is boring.

Another `map` sibling is the `foreach` function of type
`forall<a, e> (:nonempty<a>, :(a) -> e ()) -> e ()`.

```koka
pub fun foreach(ne : nonempty<a>, action : a -> e ()) : e ()
  ne.list.foreach(action)
```

Again, the implementation is boring as it delegates to `list/foreach`.

Other functions like `take`, `take-while`, `drop`, `drop-while`, `fold`s,
`scan`s, `unfold`s etc. also delegate to list functions.

```koka
pub fun take(ne : nonempty<a>, n : int = ne.length) : list<a>
  ne.list.take(n)

pub fun drop(ne : nonempty<a>, n : int = ne.length) : list<a>
  ne.list.drop(n)
```

Koka allows setting default parameters.

The more interesting difference is `last`.

```koka
pub fun length(ne : nonempty<a>) : int
  ne.tail.length + 1

pub fun last(ne : nonempty<a>) : a
  ne.tail.last.default(ne.head)
```

The `length` function always returns at least `1`.

The `last` function first applies `list/last` to the tail, which returns
`maybe<a>`; `maybe/default` then supplies the default value in case of
`Nothing`. The type of `maybe/default` is `forall<a> (:maybe<a>, :a) -> a`.

So `maximum` and `minimum` for nonempty return `a` instead of `maybe<a>`.

```koka
pub fun maximum(ne : nonempty<a>, ?cmp : (a, a) -> e order) : e a
  ne.sort.last   // in hindsight, could be a fold

pub fun minimum(ne : nonempty<a>, ?cmp : (a, a) -> e order) : e a
  ne.sort.head
```

Koka allows implicit parameter like `?cmp` there. Think of it like the Haskell
constraint `Ord a`.
So for something like a `show` function, the type would be
`fun list/show(xs : list<a>, ?show : a -> e string) : e string`,
roughly equal to Haskell `Show a => [a] -> String`.

Next: `zip`, `zip-with`, and `unzip`.

```koka
pub fun zip(n : nonempty<a>, m : nonempty<b>) : nonempty<(a, b)>
  Nonempty( head =    (n.head, m.head)
          , tail = zip(n.tail, m.tail))

pub fun unzip(ne : nonempty<(a, b)>) : (nonempty<a>, nonempty<b>)
  match ne
    Nonempty((x, y), ps) ->
      val (xs, ys) = ps.unzip
      ( Nonempty(x, xs)
      , Nonempty(y, ys))

// Or like this
pub fun unzip'(Nonempty((x, y), ps) : nonempty<(a, b)>) : (nonempty<a>, nonempty<b>)
  val (xs, ys) = ps.unzip
  ( Nonempty(x, xs)
  , Nonempty(y, ys))

pub fun zip-with(n : nonempty<a>, m : nonempty<b>, f : (a, b) -> e c) : e nonempty<c>
  Nonempty( head =       f(n.head, m.head)
          , tail = zipWith(n.tail, m.tail, f))
```

Koka allows pattern matching on structs (or inductive types with single
constructor) directly in the parameters list. This saves us up to two vertical
spaces at the cost of horizontal space.

Koka's standard list "zip with" is named `zipWith` instead of the more
conventional `zip-with`.

You can see the other functions/APIs in the repo at [nel-kk](https://github.com/LitFill/nel-kk).

### Using flake to reuse this library

We define a nix derivation like so, excuse the messiness:

```nix
{
  outputs = { self, nixpkgs, flake-utils, }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # ...

        kokaVersion = koka.version;

        nonEmptyLib = pkgs.stdenv.mkDerivation {
          pname   = "koka-non-empty";
          version = "0.1.2";
          src     = pkgs.lib.cleanSource self;

          nativeBuildInputs = [ koka ];

          buildPhase = ''
            runHook preBuild

            export KOKA_PATH="${koka}/share/koka/${kokaVersion}"

            ${koka}/bin/koka -l --target=c \
              --builddir="$PWD/.koka-build" \
              --output=nonempty \
              nonempty/nonempty.kk

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            # ...
            runHook postInstall
          '';
        };
      in
      {
        packages.nonEmptyLib = nonEmptyLib;
        packages.default = nonEmptyLib;

        kokaLibraries.nonempty = {
          path = nonEmptyLib;
          includePath = "${nonEmptyLib}/share/koka/${kokaVersion}";
          libPath = "${nonEmptyLib}/lib/koka/${kokaVersion}";
          version = kokaVersion;
          libVersion = nonEmptyLib.version;
        };
      }
    );
}
```

Then in another project we could do:

```nix
{
  description = "testing the flake of nonempty";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    nel-kk.url = "github:LitFill/nel-kk";  # you could add `?ref=` to make it "reproducible"
  };

  outputs = { self, nixpkgs, nel-kk, flake-utils, }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        koka = pkgs.koka;
        nonempty = nel-kk.packages.${system}.nonEmptyLib;
        nonemptyInclude = "${nonempty}/share/koka/${koka.version}";
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ koka ];
          shellHook = ''
            printf '{"include_dirs":["%s"]}\n' "${nonemptyInclude}" > "$PWD/koka.json"
            export KOKA_OPTIONS="--include=${nonemptyInclude}"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "my-app";
          version = "0.1.0";
          src = pkgs.lib.cleanSource self;
          nativeBuildInputs = [ koka ];
          buildInputs = [ nonempty ];
          buildPhase = ''
            koka -o my-app --include="${nonemptyInclude}" --builddir="$PWD/build" src/main.kk
          '';
          installPhase = ''
            mkdir -p "$out/bin"
            cp my-app "$out/bin/"
          '';
        };
      }
    );
}
```

First we add the repo to the inputs, and then define the library and the include path:

```nix
nonempty        = nel-kk.packages.${system}.nonEmptyLib;
nonemptyInclude = "${nonempty}/share/koka/${koka.version}";
```

In the devShell, I use nix to generate `koka.json` so the LSP can find the nonempty
list library.

```json
{
  "include_dirs": ["/nix/store/...-koka-non-empty-0.1.2/share/koka/3.2.9"]
}
```

It also sets `$KOKA_OPTIONS` to add the `--include` flag so we do not need to
manually supply it to the compiler.

In the derivation we register the library:

```nix
buildInputs = [ nonempty ];
```

### If you hate nix for some reason

You could vendor the nonempty/nonempty.kk file because it is a dependency-free,
single-module-style library.

## Result

Now we have a port of the NonEmpty list library and a way to use it either via nix
or as a single-module library.

The repo is at [LitFill/nel-kk](https://github.com/LitFill/nel-kk).

We use it as a normal import:

```koka
module main

import nonempty

// or if you vendor it at ./lib/nonempty.kk
import lib/nonempty

fun main() : console ()
  val nel : nonempty<int> = 1 <:: 2 <:: [3]
  nel.println
  nel.map(_+ 66).foreach(_.println)
  nel.reverse.println
```

Then build it either with koka or nix build:

```sh
# devShell adds --include flag to KOKA_OPTIONS so we could omit it:
koka -o main main.kk

# or via nix:
nix build .
```

Or run it:

```sh
koka -e main.kk

# or
nix run .
```

The output would look like this:

```koka
Nonempty(head=1, tail=[2,3])
67
68
69
Nonempty(head=3, tail=[2,1])
```

## Trade-offs and Limitations

At the time of writing, Koka released the std/async stuff. Somewhere in it there
is a comment noting the need for a `list1` data structure.

Currently this library is just a port of Haskell Data.List.NonEmpty, with some
additions based on Koka's list API.

Functions that could not guarantee the nonempty invariant return a list instead.
The library is not optimized yet, but Koka has a good performance story.

## About me

Thank you for reading. You could find me as [@razzy_ar](https://x.com/razzy_ar)
at X the everything app, as [LitFill](https://github.com/LitFill) at GitHub, or
at
[Signal](https://signal.me/#eu/adwpQptqUZIrULYfkcjSZjeMY6rFdWaA0k8_NM1J7scxGGDk4V5IsLTQk-2Rl2Wz).

Feel free to say something nice (or not) and thanks for reading.
