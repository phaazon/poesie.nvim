-- Plugin configuration mapper.
--
-- Each plugin entry consists of the following keys:
--
-- - "rename": rename the plugin so that it’s exposed a the given name.
-- - "branch": specify the branch to checkout this plugin at.
-- - "enable": state whether or not we should be using this plugin.
-- - "depends": list of other plugins this plugin depends on.
-- - "after": runs some Vim commands after installation.
-- - "global_setup": global configuration.
-- - "config": configuration of the plugin — the plugin most expose a public
--   Lua "setup" function accepting the configuration object.
--
-- In the case where the plugin doesn’t support the "setup" + "config" situation, some local overrides might be provided
-- to still allow configuring those plugins via this mechanism.

local M = {}

local plugin_exists = require'poesie.plugin'.plugin_exists

local function setup_override_nvim_tree(c)
  local bindings = {}
  local tree_cb = require'nvim-tree.config'.nvim_tree_callback

  if c.keybindings ~= nil then
    for key, value in pairs(c.keybindings) do
      bindings[key] = tree_cb(value)
    end

    vim.g.nvim_tree_bindings = bindings
  end
end

local function setup_override_lsp_extensions(c)
  if c.rust_analyzer_inlay_hints ~= nil then
    local rust_conf = c.rust_analyzer_inlay_hints
    local au_groups = rust_conf.au_groups or {
      'BufEnter',
      'BufWinEnter',
      'BufWritePost',
      'InsertLeave',
      'TabEnter'
    }

    local au_string = 'au '
    for i, au_group in ipairs(au_groups) do
      if i == 1 then
        au_string = au_string .. au_group
      else
        au_string = au_string .. ',' .. au_group
      end
    end

    au_string = au_string .. " *.rs :lua require'lsp_extensions'.inlay_hints { "
    au_string = au_string .. 'highlight = ' .. (rust_conf.highlight or 'Comment') .. ','
    au_string = au_string .. 'prefix = ' .. (rust_conf.prefix or ' » ') .. ','
    au_string = au_string .. 'aligned = ' .. (rust_conf.aligned or 'false') .. ','
    au_string = au_string .. 'only_current_line = ' .. (rust_conf.only_current_line or 'false') .. ','

    au_string = au_string .. 'enabled = { '
    for _, enabled in pairs(rust_conf.enabled or { 'ChainingHint' }) do
      au_string = au_string .. enabled
    end
    au_string = au_string .. ' }'

    vim.cmd(au_string)
  end
end

local function setup_override_telescope(c)
  local sorters = {
    get_fuzzy_file = require'telescope.sorters'.get_fuzzy_file,
    get_generic_fuzzy_sorter = require'telescope.sorters'.get_generic_fuzzy_sorter,
    get_levenshtein_sorter = require'telescope.sorters'.get_levenshtein_sorter,
    get_fzy_sorter = require'telescope.sorters'.get_fzy_sorter,
    fuzzy_with_index_bias = require'telescope.sorters'.fuzzy_with_index_bias,
  }

  local previewers = {
    vim_buffer_cat = require'telescope.previewers'.vim_buffer_cat.new,
    vim_buffer_vimgrep = require'telescope.previewers'.vim_buffer_vimgrep.new,
    vim_buffer_qflist = require'telescope.previewers'.vim_buffer_qflist.new,
    cat = require'telescope.previewers'.cat.new,
    vimgrep = require'telescope.previewers'.vimgrep.new,
    qflist = require'telescope.previewers'.qflist.new,
  }

  local config = {}

  if c.defaults.file_sorter ~= nil then
    config.file_sorter = sorters[c.defaults.file_sorter]
  end

  if c.defaults.generic_sorter ~= nil then
    config.generic_sorter = sorters[c.defaults.generic_sorter]
  end

  if c.defaults.file_previewer ~= nil then
    config.file_previewer = previewers[c.defaults.file_previewer]
  end

  if c.defaults.grep_previewer ~= nil then
    config.grep_previewer = previewers[c.defaults.grep_previewer]
  end

  if c.defaults.qflist_previewer ~= nil then
    config.qflist_previewer = previewers[c.defaults.qflist_previewer]
  end

  if c.defaults.mappings ~= nil then
    local overriden_mappings = {}
    for mode, mappings in pairs(c.defaults.mappings) do
      local maps = {}
      for key, action in pairs(mappings) do
        maps[key] = require'telescope.actions'[action]
      end

      overriden_mappings[mode] = maps
    end

    config.mappings = overriden_mappings
  end

  require'telescope'.setup({ defaults = config })
end

-- FIXME: we need to allow passing configuration to telescope.setup; we should probably remove those overrides and move
-- them in the override of telescope; it’s ugly but that extension system is by itself very annoying so meh meh meh
-- FIXME: ensure the overrides are made _after_ the override of telescope… hard?
local function setup_override_telescope_fzy_native()
  require'telescope'.load_extension('fzy_native')
end

local function setup_override_telescope_fzf_native()
  require'telescope'.load_extension('fzf')
end

local function setup_override_octo(c)
  require'telescope'.load_extension('octo')
  require'octo'.setup(c)
end

local setup_overrides = {
  ['kyazdani42/nvim-tree.lua'] = setup_override_nvim_tree,
  ['nvim-lua/lsp_extensions.nvim'] = setup_override_lsp_extensions,
  ['nvim-telescope/telescope.nvim'] = setup_override_telescope,
  ['nvim-telescope/telescope-fzy-native.nvim'] = setup_override_telescope_fzy_native,
  ['nvim-telescope/telescope-fzf-native.nvim'] = setup_override_telescope_fzf_native,
  ['pwntester/octo.nvim'] = setup_override_octo,
}

local function packer_interpret(plugins)
  if not plugin_exists('packer') then
    return
  end

  error('packer doesn’t work as expected and hence support is not complete; sorry, have a hug')

  vim.cmd [[packadd packer.nvim]]
  require('packer').startup(function(use)
    -- the first plugin needed is obviously packer, so that we can bootstrap it once and have it automatically updated
    -- etc.; however, if it’s already present in the user configuration, we authorize specific configuration to be
    -- passed, because we are cool
    if plugins["wbthomason/packer.nvim"] == nil then
      plugins["wbthomason/packer.nvim"] = {{}}
    end

    for plug_name, plug_conf in pairs(plugins) do
      local original_plug_name = plug_name
      local conf = { plug_name }

      if plug_conf.rename ~= nil and type(plug_conf.rename) == 'string' then
        conf.as = plug_conf.rename

        -- used later for configuration purposes
        plug_name = plug_conf.rename
      else
        plug_name = plug_name:match(".*/(.*)")
      end

      if plug_conf.branch ~= nil and type(plug_conf.branch) == 'string' then
        conf.branch = plug_conf.branch
      end

      if plug_conf.enable ~= nil and type(plug_conf.enable) == 'boolean' then
        conf.disable = not plug_conf.enable
      end

      if plug_conf.depends ~= nil and type(plug_conf.depends) == 'table' then
        local requires = {}

        for _, dependency in pairs(plug_conf.depends) do
          requires[#requires + 1] = { dependency }
        end

        conf.requires = requires
      end

      if plug_conf.after ~= nil and type(plug_conf.after) == 'string' then
        conf.run = plug_conf.after
      end

      if plug_conf.global_setup ~= nil and type(plug_conf.global_setup) == 'table' then
        for key, value in pairs(plug_conf.global_setup) do
          vim.g[key] = value
        end
      end

      if plug_conf.config ~= nil and type(plug_conf.config) == 'table' then
        conf.config = function()
          local plugin = require(plug_name)

          -- look for setup overrides first
          --
          -- otherwise, if the plugin exposes a setup function, configure it by passing the local configuration
          -- otherwise, check if we have local override for it
          if setup_overrides[original_plug_name] ~= nil then
            setup_overrides[original_plug_name](plug_conf.config)
          elseif plugin.setup ~= nil then
            plugin.setup(plug_conf.config)
          end
        end
      end

      use(conf)
    end
  end)
end

local function paq_interpret(plugins)
  vim.cmd [[packadd paq-nvim]]

  if not plugin_exists('paq-nvim') then
    error('paq not installed ffs')
    return
  end

  local paq = require'paq-nvim'.paq

  if plugins['savq/paq-nvm'] == nil then
    paq { 'savq/paq-nvim', opt = true }
  end

  for plug_name, plug_conf in pairs(plugins) do
    if plug_conf.enable == nil or plug_conf.enable then
      local original_plug_name = plug_name
      local conf = { plug_name }

      if plug_conf.rename ~= nil and type(plug_conf.rename) == 'string' then
        conf.as = plug_conf.rename

        -- used later for configuration purposes
        plug_name = plug_conf.rename
      else
        plug_name = plug_name:match(".*/(.*)")

        local plug_name_alt = plug_name:match('(.*)%.')
        if plug_name_alt ~= nil then
          plug_name = plug_name_alt
        end
      end

      if plug_conf.branch ~= nil and type(plug_conf.branch) == 'string' then
        conf.branch = plug_conf.branch
      end

      if plug_conf.after ~= nil and type(plug_conf.after) == 'string' then
        conf.run = plug_conf.after
      end

      if plug_conf.global_setup ~= nil and type(plug_conf.global_setup) == 'table' then
        for key, value in pairs(plug_conf.global_setup) do
          vim.g[key] = value
        end
      end

      paq(conf)

      if plug_conf.config ~= nil and type(plug_conf.config) == 'table' then
        -- look for setup overrides first
        --
        -- otherwise, if the plugin exposes a setup function, configure it by passing the local configuration
        -- otherwise, check if we have local override for it
        if setup_overrides[original_plug_name] ~= nil then
          setup_overrides[original_plug_name](plug_conf.config)
        elseif plugin_exists(plug_name) then
          local plugin = require(plug_name)

          if plugin.setup ~= nil then
            plugin.setup(plug_conf.config)
          end
        end
      end
    end
  end
end

local packagers = {
  packer = packer_interpret,
  paq = paq_interpret,
}

local function is_valid_packager(name)
  return packagers[name] ~= nil
end

function M.interpret(c)
  -- Get the package manager to use.
  if c.packager == nil or not is_valid_packager(c.packager) then
    error('you must specify a valid package manager to use')
    return
  end

  local packager = c.packager
  local plugins = c.plugins or {}

  packagers[packager](plugins)
end

return M
