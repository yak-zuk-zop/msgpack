
-record(options, {
    spec = new :: new | old,
    allow_atom = pack :: none | pack | nonempty_list(atom() | binary()),
    string = as_list :: msgpack:string_method(),
    validate_string = false :: boolean(),
    map_format = map :: msgpack:map_type()
}).
