# create-sdl3-bindings

Generates a low-level Perl XS binding for SDL3 (or any other C library with
a similarly regular public API) straight from its headers. Nothing about the
library is hard-coded: clang parses the headers, every declaration is
classified by its C type, and the generator writes an installable
ExtUtils::MakeMaker distribution.

The SDL sources are a git submodule under `vendor/SDL`.

## Requirements

- perl 5.36 or newer with the modules listed in `cpanfile`
- a `clang` binary (tested with clang 17) for the AST dump; the library
  itself is not needed to generate the binding
- to build the generated distribution: a C11 compiler, `pkg-config` and an
  installed SDL3 (`pkg-config --cflags --libs sdl3` must work)

## Usage

    bin/create-sdl3-bindings --help
    bin/create-sdl3-bindings inspect --details          # what would be bound, and why not
    bin/create-sdl3-bindings generate --output ../perl-sdl3

    cd ../perl-sdl3 && perl Makefile.PL && make && make test

Headers and functions are selected with `--include-header`,
`--exclude-header` and `--exclude-function` (regular expressions). By default
the test library, `SDL_main.h`, the libc wrappers of `SDL_stdinc.h` and the
compatibility names of `SDL_oldnames.h` are left out. Use `--clang clang-17`
when the binary is not on the path under the plain name.

Building SDL3 from the submodule for local testing:

    cmake -S vendor/SDL -B .build/sdl3 -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PWD/.build/prefix
    ninja -C .build/sdl3 install
    export PKG_CONFIG_PATH=$PWD/.build/prefix/lib/pkgconfig LD_LIBRARY_PATH=$PWD/.build/prefix/lib

## Automatic releases

The workflow `.github/workflows/sdl3-release.yml` publishes the binding for
every SDL 3 release to
[davenonymous/perl-sdl3-xs](https://github.com/davenonymous/perl-sdl3-xs).
libsdl-org/SDL cannot trigger it, so it polls the upstream `release-3.X.Y`
tags once a day and publishes every release newer than the last published
one (only the newest when nothing is published yet). It can also be started
by hand with a specific SDL tag.

For each release it builds SDL from that tag, generates the binding,
runs `make disttest` on it and then replaces the content of the target
repository's main branch with the generated distribution, tags it and
creates a GitHub release with the `make dist` tarball attached. SDL
`release-3.4.18` becomes version `3.004018`, tagged `v3.004018`.

The workflow needs the repository secret `SDL3_XS_TOKEN`: a fine-grained
personal access token for the target repository with "Contents: read and
write".

## How it works

1. `BindGen::Clang` runs clang three times on the umbrella header: a JSON
   AST dump (declarations, types, doc comments), a text AST dump (only
   there the printf format attribute carries its argument index) and
   `-E -dD` (macros with the header that defines them).
2. `BindGen::Parser` turns the AST into a `BindGen::Model`: headers,
   functions, structs and unions (including nested unnamed ones), enums,
   typedefs and macros. `BindGen::CType` parses clang's type spellings.
3. `BindGen::MacroProbe` compiles one probe per object-like macro so the
   compiler decides which macros are constant expressions of a
   representable type.
4. `BindGen::Planner` maps every parameter, return value and struct field
   through `BindGen::Mapper` to a `BindGen::Mapping` and records every
   declaration it cannot bind, with the reason, in `BindGen::Report`.
5. `BindGen::Emitter` writes the distribution from the plan and the
   Template Toolkit templates in `templates/`.

## What the generated binding looks like

- `SDL3` loads the XS code and re-exports everything; `SDL3::API::<Header>`
  holds the functions and constants of one header (`SDL3::API::Video` for
  `SDL_video.h`); structs and unions are classes directly below `SDL3::`
  (`SDL3::Rect`, `SDL3::Event`), nested unnamed records become
  `SDL3::GamepadBinding::Input`.
- Functions keep their C names and argument order. Constants are exported
  with the type the compiler sees via `_Generic`, so no values are
  evaluated at generation time.
- Pointers to structs are blessed pointer objects with one XS accessor per
  field; objects created from Perl own their memory, everything else is
  borrowed. `void *` and other untyped memory is a `SDL3::Pointer`.
- Pointer-to-scalar and pointer-to-pointer parameters are out parameters:
  pass a scalar reference, a pointer object or undef.
- A callback parameter takes a code ref; the paired `void *userdata`
  parameter takes any scalar. One trampoline per callback type calls back
  into Perl. The holder keeping the code ref alive is never freed.
- printf-style variadic functions take their fixed arguments plus one
  preformatted message.
- `char *` results become Perl strings. When the function's doc comment
  names the deallocator given with `--free-function` (SDL_free by default)
  the C memory is freed after copying; otherwise it is only copied and the
  report notes it.
- Doxygen comments become POD. `bindgen-report.txt` in the output lists
  every skipped declaration and why.
