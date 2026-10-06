MsgPack
=======

A native Erlang library for packing/unpacking *MessagePack* format.

Usage
-----

```erlang
Bin = msgpack:pack(ErlangTerm),
{ok, ErlangTerm} = msgpack:unpack(Bin).
```

### Stream decoding

When a binary contains more than one term, use the `unpack_stream` function.

```erlang
{Term0, Rest0} = msgpack:unpack_stream(Bin),
{Term1, Rest1} = msgpack:unpack_stream(Rest0),
```

In the case of large data split into several binary chunks it is better to use
the following decoding functions. They help you process an incoming binary stream
without waiting for (and collecting) the whole binary.

```erlang
{continue, State} = msgpack:decode_start(SmallBin, []),
{Term, Rest} = msgpack:decode_continue(RestBin, State),
```

Options
-------

### `{spec, new | old}`

Default is `new`. Major difference between the old and new specs is:

- raw family (`0xa0 - 0xbf`, `0xda`, `0xdb`) becomes new str family
- `0xd9` is introduced as str8
- new bin types (`0xc4, 0xc5, 0xc6` as bin8, bin16, bin32)
- new ext types (`0xc7, 0xc8, 0xc9` as ext8, ext16, ext32)
- new fixext types (`0xd4, 0xd5, 0xd6, 0xd7, 0xd8` as fixext1, fixext2, fixext4, fixext8, fixext16)

Old spec mode does not handle these new types and returns an error instead. To use
[old spec](https://github.com/msgpack/msgpack/blob/master/spec-old.md) mode,
this option must be set explicitly.

```erlang
Bin = msgpack:pack(Term, [{spec, old}]),
{ok, Term} = msgpack:unpack(Bin, [{spec, old}]).
```

### `{allow_atom, none | pack | [atom()]}`

- none | pack Only for packing. Atoms are packed as binaries. Default value is `pack`.
With `none` any atom raises a badarg error.
- [atom()] Both for packing and unpacking. In packing, if an atom is in this list
it is encoded as a binary. In unpacking, a MessagePack binary is decoded as an atom
using `erlang:binary_to_existing_atom/2` with `utf8` encoding.
An empty list is equivalent to `none`.

### `{string, as_binary | as_list}`

A switch to choose the term style of `str` type for packing and unpacking.
Available in the new spec only. Default is `as_list`.

- unpacking

```
msgpack/mode  as_binary    as_list
------------+-----------+-----------
    bin        binary()    binary()
    str        binary()    string()
```

- packing

```
 term/mode    as_binary     as_list
-----------+-------------+------------
 binary()    str*/bin       bin         
 string()    array of int   str*/array  
 list()      array          array       
```

- \* packs as `str` if it is valid.

### `{validate_string, boolean()}`

UTF-8 validation at unpacking from `str` type is enabled. Default value is `false`.

### `{map_format, map | jsx}`

Used for both packing and unpacking. Default value is `map`.

```erlang
msgpack:pack(#{<<"key">> => <<"value">>}, []).
msgpack:pack(#{<<"key">> => <<"value">>}, [{map_format, map}]).
msgpack:pack([{<<"key">>, <<"value">>}], [{map_format, jsx}]).
```

Misc
----

### Float type

The float type of MessagePack represents an IEEE 754 floating-point number, so it
can also represent `nan` and `infinity`. When unpacking, the library returns `nan`,
`positive_infinity`, and `negative_infinity`.

Cheatsheet
----------

```shell
make compile
```

```shell
make tests
```

```shell
make xref
make dialyzer
