<br clear="all" />
<p align="center">
  <img src="https://github.com/user-attachments/assets/b23b4325-abde-463a-a1d1-8d42f4dabd25" width="200" height="200" alt="Image" />
  <br>
  <b>UnPack is a minimal layer on top of vim.pack</b>
</p>
<br clear="all" />

> [!IMPORTANT]
>
> `vim.pack` is currently under development in the `neovim-nightly` branch.

## Demo

Example [config](https://github.com/mezdelex/neovim) using UnPack as daily driver.

https://github.com/user-attachments/assets/7ad14bac-70f0-4ded-aed0-308fefb767e9

## Installation

Add these lines to your init.lua:

```lua
vim.pack.add({ "https://github.com/mezdelex/unpack.nvim" }, { confirm = false })
```

## Setup

`UnPack` automatically loads its default config on startup via `plugin` directory.
Call setup right after the installation with your preferred options if you don't like the defaults.
Defaults are set with minimal interaction in mind, so if you want to be notified about all the changes, set `confirm` to true and `force` to false.

Available options:

```lua
---@class UnPack.Config.UserOpts
--- Options for vim.pack.add
---@field add_options? vim.pack.keyset.add
--- Options for vim.pack.update
---@field update_options? vim.pack.keyset.update
```

See `:h vim.pack.add` and `:h vim.pack.update` opts.

> [!TIP]
>
> Make sure you set `vim.g.mapleader` beforehand.

```lua
require("unpack").setup({
    -- example optional setup call
    add_options = { confirm = true }, -- default false
    update_options = { force = false }, -- default true
})
```

## Spec

This layer extends `vim.pack.Spec` to allow single file configurations.

```lua
---@class UnPack.Spec : vim.pack.Spec
---@field config? fun()
---@field defer? boolean
---@field dependencies? UnPack.Spec[]
```

It also leverages `PackChanged` event triggered by `vim.pack` internals to run plugin build hooks. The same `command` that is fired inside the event is provided as a standalone one. See `Commands` section.

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
	data = {
        build = "your build --command",
        conflicts = { "conflicting_file_name1.dll", "conflicting_file_name2.dll" }
    },
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
			src = "https://github.com/<vendor>/plugin2",
		},
	},
	src = "https://github.com/<vendor>/plugin3",
}
```

### Build

UnPack expects a `build` field inside `data` table for the build hook, so make sure you add it like shown in the first example.
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
        local kind = args.data.kind ---@type string

        if kind == "install" or kind == "update" then
            local spec = args.data.spec ---@type UnPack.Spec

            commands.build({ spec })
        end
    end,
    group = group,
})
```

### Conflicts

Under WinOS, there are some permission problems related to the write rights on locked files and this affects the build hook when updating some plugins like `blink.cmp`.
To address this, together with the `build` hook, `UnPack` expects you to use `conflicts` hook inside the `data` table. This is like this because the `build` hook
will eventually be handled by the plugin itself with the incoming `spec` changes as we stated before, so it makes sense to keep them together.

Until then, this is the workaround for WinOS users:

```lua
return {
    config = function()
        -- example configuration
        require("blink.cmp").setup({
            completion = {
                documentation = { auto_show = true },
            },
            keymap = { preset = "enter" },
        })
    end,
    data = {
        build = "cargo build --release",
        conflicts = { "blink_cmp_fuzzy.dll" },
    },
    defer = true,
    src = "https://github.com/saghen/blink.cmp",
}
```

### Defer

Every spec marked with `defer = true` is going to be deferred using `vim.schedule` to avoid UI render delay. Dependencies follow the same rules.

### Dependencies

The dependencies handling logic is pretty simple: the plugins are going to be loaded in order, so make sure to add the dependencies in order too.
For example, if any of your plugins relies on `plenary` as a dependency, add it in the first plugin that requires it following your `plugins` directory name order, and that's pretty much it.

## Commands

> [!NOTE]
>
> All the notifications are wrapped in a `vim.schedule` call to avoid command line overflow.
> If you want to see the recap after executing any command, use `:messages`.

The commands provided are:

| Command      | Description                                                                                                                             |
| :----------- | :-------------------------------------------------------------------------------------------------------------------------------------- |
| `PackBuild`  | Iterates over all the plugin specs and runs all the build hooks. _(Triggered automatically on `PackChanged` event per changed package)_ |
| `PackClean`  | Removes any plugin present in your packages directory that doesn't exist as a plugin spec and cleans stale conflicts if any.            |
| `PackLoad`   | Loads all the plugins in your `plugins` directory. _(Runs on `VimEnter`; exposed for build timeouts)_                                   |
| `PackUpdate` | Updates all the plugins present in your packages directory.                                                                             |

You can also use them this way if you prefer:

```lua
    local commands = require("unpack.commands")

    vim.keymap.set("n", "<your-keymap>", commands.build)
    vim.keymap.set("n", "<your-keymap>", commands.clean)
    vim.keymap.set("n", "<your-keymap>", commands.load)
    vim.keymap.set("n", "<your-keymap>", commands.update)
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
      ggg
