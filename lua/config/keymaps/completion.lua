-- blink.cmp `keymap` option, consumed by lua/plugins/completion.lua.
return {
  preset = "default",

  ["<Tab>"] = {
    "select_and_accept",
    "snippet_forward",
    "fallback",
  },

  ["<S-Tab>"] = {
    "snippet_backward",
    "fallback",
  },
}
