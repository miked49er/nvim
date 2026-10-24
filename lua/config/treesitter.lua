local M = {}

-- Filetypes whose parser has a different name than the filetype.
M.parser_aliases = {
  jsonc = 'json',
}

--- Start treesitter highlighting and indent per buffer on FileType for every
--- listed language. Missing parsers (async install) are silently skipped.
function M.setup(languages)
  for ft, lang in pairs(M.parser_aliases) do
    vim.treesitter.language.register(lang, ft)
  end

  local wanted = {}
  for _, lang in ipairs(languages) do
    wanted[lang] = true
  end
  for ft, lang in pairs(M.parser_aliases) do
    if wanted[lang] then wanted[ft] = true end
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('config_treesitter_start', { clear = true }),
    callback = function(args)
      local lang = vim.treesitter.language.get_lang(args.match) or args.match
      if not (wanted[args.match] or wanted[lang]) then return end
      if pcall(vim.treesitter.start, args.buf, lang) then
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
  })
end

return M
