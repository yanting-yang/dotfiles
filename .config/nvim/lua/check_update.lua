-- Paths to store state
local state_dir = vim.fn.stdpath("state")
local time_file = state_dir .. "/update_check_time"
local version_file = state_dir .. "/latest_neovim_version"

-- Helper function to print the message
local function notify_new_version(latest)
    local current = vim.version()
    local current_str = string.format("%d.%d.%d", current.major, current.minor, current.patch)
    local latest_str = string.format("%d.%d.%d", latest.major, latest.minor, latest.patch)

    if vim.version.cmp(latest, current) > 0 then
        vim.schedule(function()
            vim.notify(
                string.format("✨ New Neovim version available: %s (You have %s)", latest_str, current_str),
                vim.log.levels.INFO
            )
        end)
    else
        vim.schedule(function()
            vim.notify(
                string.format("✅ Neovim is up to date: %s", current_str),
                vim.log.levels.INFO
            )
        end)
    end
end

-- 1. Function to run the expensive network check
local function check_update_network()
    local url = "https://github.com/neovim/neovim/releases/latest"

    vim.system({ "curl", "-Ls", "-o", "/dev/null", "-w", "%{url_effective}", url }, { text = true }, function(obj)
        if obj.code ~= 0 then return end -- Silent fail on network error

        local output = obj.stdout or ""
        local latest_tag = output:match("([^/]+)$")
        if not latest_tag then return end

        local latest = vim.version.parse(latest_tag)
        local current = vim.version()

        local f = io.open(version_file, "w")
        if f then
            f:write(latest_tag)
            f:close()
        end

        -- B. Notify user now
        notify_new_version(latest)
    end)
end

-- 2. Function to check the local cache file (runs fast on every startup)
local function check_cached_version()
    local f = io.open(version_file, "r")

    if not f then
        vim.schedule(function()
            vim.notify("No cached Neovim version info found.", vim.log.levels.INFO)
        end)
        return
    end

    local cached_tag = f:read("*a")
    f:close()

    local latest = vim.version.parse(cached_tag)
    notify_new_version(latest)
end

-- 3. Main Controller
local function run_daily_check()
    -- Get last check time
    local f = io.open(time_file, "r")
    local last_check = 0
    if f then
        local content = f:read("*n")
        if content then last_check = content end
        f:close()
    end

    local now = os.time()
    -- If 24 hours (86400 seconds) have passed
    if (now - last_check) > 86400 then
        -- Update timestamp immediately
        local w = io.open(time_file, "w")
        if w then
            w:write(now)
            w:close()
        end
        -- Run network check
        check_update_network()
    else
        -- Just check the cached file (fast)
        check_cached_version()
    end
end

run_daily_check()
