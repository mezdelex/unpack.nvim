<br clear="all" />
<p align="center">
  <img src="https://github.com/user-attachments/assets/b23b4325-abde-463a-a1d1-8d42f4dabd25" width="300" height="200" alt="Image" />
  <br>
  <b>unpack is a minimal layer on top of vim.pack</b>
</p>
<br/>

## Installation

Add this line to your init.lua:

```lua
vim.pack.add({ "https://github.com/mezdelex/unpack.nvim" }, { confirm = false })
```

## Setup

`unpack` automatically loads its default config on startup via `plugin` directory.
Call setup right after the installation with your preferred options if you don't like the defaults.
Defaults are set with minimal interaction in mind, so if you want to be notified about all the changes, set `confirm` to true and `force` to false.

Available options:

```lua
---@class Unpack.Config.UserOpts
---@field add_options vim.pack.keyset.add?
---@field update_options vim.pack.keyset.update?
```

See `:h vim.pack.add` and `:h vim.pack.update` opts.

> [!TIP]
>
> Make sure you set `vim.g.mapleader` beforehand.

```lua
-- example optional setup call
require("unpack").setup({
    add_options = { confirm = true }, -- default false
    update_options = { force = false }, -- default true
})
```

## Spec

This layer extends `vim.pack.Spec` to allow single file configurations.

```lua
---@class Unpack.Spec : vim.pack.Spec
---@field config fun()?
---@field defer boolean?
---@field dependencies Unpack.Spec[]?
```

It also leverages `PackChanged` event triggered by `vim.pack` internals to run plugin build hooks.

Example [config](https://github.com/mezdelex/neovim) using unpack as daily driver.

Example plugin spec setups under `/lua/plugins/`:

```lua
return {
	config = function()
		...
	end,
	data = { build = "your build --command" },
	defer = true,
	src = "https://github.com/<vendor>/plugin1",
}
```

```lua
return {
	config = function()
		...
	end,
	defer = true,
	dependencies = {
		{
            defer = true,
            src = "https://github.com/<vendor>/plugin2"
        },
	},
	src = "https://github.com/<vendor>/plugin3",
}
```

### Build

unpack expects a `build` field inside `data` table for the build hook, so make sure you add it like shown in the first example.
This is because `vim.pack` handles the event trigger internally and exposes `vim.pack.Spec`, not the extended one, so we need to rely on that table.
The build hook is planned to be part of and handled by the plugin itself, that's why there's no build hook exposed on purpose, but for now this is the workaround.

For reference, this is the `autocmd` that listens to the event triggered by `vim.pack` internals whenever there's a change in any package.

> [!NOTE]
>
> This is already set, you don't need to worry about it.

```lua
vim.api.nvim_create_augroup(group, { clear = true })
vim.api.nvim_create_autocmd("PackChanged", {
    callback = function(args)
        if args.data.kind == "install" or args.data.kind == "update" then
            commands.build(args.data)
        end
    end,
    group = group,
})
```

### Defer

Every spec marked with `defer = true` is going to be deferred using `vim.schedule` to avoid UI render delay. Dependencies follow the same rules.

### Dependencies

The dependencies handling logic is pretty simple: the plugins are going to be loaded following the `plugins` directory name order, so make sure to add the dependencies properly.
For example, if any of your plugins relies on given dependency, add it in the first plugin that requires it following your `plugins` directory name order, and that's pretty much it.
Note that unpack treats every `spec` separately, so you could still include the dependencies in order, defer a specific plugin and still eagerly load its dependencies so they would be available for the following eagerly loaded ones that might require those dependencies.
Whatever makes more sense to you.

## Commands

> [!NOTE]
>
> If you want to see the recap after executing any command, use `:messages`.

The commands provided are:

| Command          | Description                                                                                |
| :--------------- | :----------------------------------------------------------------------------------------- |
| `:Unpack clean`  | Removes any plugin present in your packages directory that doesn't exist as a plugin spec. |
| `:Unpack update` | Updates all the plugins present in your packages directory.                                |

You can also use them this way if you prefer:

```lua
local unpack = require("unpack")

vim.keymap.set("n", "<your-keymap>", unpack.clean)
vim.keymap.set("n", "<your-keymap>", unpack.update)
```

## Roadmap

- [x] Single config file
- [x] Defer behavior
- [x] Simple dependency handling
- [x] Commands
- [x] Better error handling
- [x] Performance improvements
- [x] CI
  - [x] Style check job (stylua)
  - [x] Tests check job (busted)
    - [x] commands
    - [x] config
    - [x] extensions
    - [x] unpack
  - [x] Doc generation job (panvimdoc)
- [x] Add dependabot
- [x] Enforce PR ruleset
