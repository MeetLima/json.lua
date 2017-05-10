package = "lima-json"
version = "scm-1"

source = { url = "git://github.com/MeetLima/json.lua.git" }

description = {
   summary = "Lima fork of json.lua.",
   detailed = [[
      Very simple single-file json module.
      This fork only targets Lua 5.3.
   ]],
   homepage = "http://github.com/MeetLima/json.lua",
   license = "MIT/X11",
}

dependencies = { "lua >= 5.3" }

build = {
    type = "none",
    install = { lua = { ["json"] = "json.lua" } },
}
