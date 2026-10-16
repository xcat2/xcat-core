-- Transaction dependencies are not available before unpacking.
if arg[2] and tonumber(arg[2]) == 1 then return end

local function contents(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local data = handle:read("*a")
    handle:close()
    return data
end

local templates = { contents(template_dir .. "/xcat.conf.apach24"),
                    contents(template_dir .. "/xcat.conf.apach22") }

for _, active in ipairs({ "/etc/httpd/conf.d/xcat.conf",
                          "/etc/apache2/conf.d/xcat.conf" }) do
    -- A symlink or any other non-regular path is treated as locally managed.
    if posix.stat(active, "type") == "regular" then
        local current = contents(active)
        for _, template in ipairs(templates) do
            if current and current == template then
                os.remove(active)
                break
            end
        end
    end
end
