# ![json.lua](https://cloud.githubusercontent.com/assets/3920290/9281532/99e5e0cc-42bd-11e5-8fce-eaff2f7fc681.png)

## Presentation

This is Lima's version of the JSON wheel. It is a fork of [rxi/json.lua](https://github.com/rxi/json.lua).

Typically we only use the encoder with Lua 5.3. Consider other use cases unsupported (see [Alternatives](#Alternatives)).

## Dependencies

None except Lua 5.3.

## Usage

    > json = require "json"
    > json.encode({foo = { bar = "baz", answer = 42 }})
    {
      "foo":{
        "bar":"baz",
        "answer":42
      }
    }
    > json.encode({foo = { bar = "baz", answer = 42 }}, false) -- no pretty printing
    {"foo":{"bar":"baz","answer":42}}

## Alternatives

For a full-featured, pure Lua + LPeg JSON encoder / decoder, check out [luajson](https://github.com/harningt/luajson).

Otherwise, there are plenty of options [in LuaRocks](https://luarocks.org/labels/json).

## License

This library is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE.txt](LICENSE.txt) for details.

