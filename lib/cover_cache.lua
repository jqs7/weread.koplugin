--[[--
WeRead cover download and local disk cache.

Covers from shelf sync are stored under
{data_dir}/cache/weread/covers/{bookId}.jpg
--]]--

local DataStorage = require("datastorage")
local RenderImage = require("ui/renderimage")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local WeRead = require("lib.weread")

local CoverCache = {}

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/weread/covers/"

local function ensureDir()
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then
        util.makePath(CACHE_DIR)
    end
end

local function countPath(path)
    local mode = lfs.attributes(path, "mode")
    if mode == "file" then
        return 1, lfs.attributes(path, "size") or 0
    end
    if mode ~= "directory" then
        return 0, 0
    end

    local files = 0
    local bytes = 0
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            local f, b = countPath(path .. "/" .. entry)
            files = files + f
            bytes = bytes + b
        end
    end
    return files, bytes
end

local function formatBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then
        return string.format("%d B", bytes)
    end
    if bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    end
    if bytes < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
    return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
end

function CoverCache.cacheDir()
    return CACHE_DIR
end

function CoverCache.pathFor(book_id)
    if not book_id or book_id == "" then
        return nil
    end
    return CACHE_DIR .. tostring(book_id) .. ".jpg"
end

function CoverCache.formatBytes(bytes)
    return formatBytes(bytes)
end

function CoverCache.stats()
    local files, bytes = countPath(CACHE_DIR)
    return { files = files, bytes = bytes }
end

--- Load a cached cover BlitBuffer.
function CoverCache.loadCached(book_id)
    local path = CoverCache.pathFor(book_id)
    if not path or lfs.attributes(path, "mode") ~= "file" then
        return nil
    end
    local bb = RenderImage:renderImageFile(path)
    if not bb then
        logger.info("weread cover: corrupt cache, removing", path)
        os.remove(path)
    end
    return bb
end

--- Load cached cover bytes (for EPUB embedding).
function CoverCache.loadCachedBytes(book_id)
    local path = CoverCache.pathFor(book_id)
    if not path or lfs.attributes(path, "mode") ~= "file" then
        return nil
    end
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    if not data or #data == 0 then
        return nil
    end
    return data
end

--- Download a cover and write it to disk.
function CoverCache.fetch(client, book_id, url)
    if not client or not book_id or not url or url == "" then
        return nil, "missing args"
    end

    url = WeRead.normalize_cover_url(url)

    local cached = CoverCache.loadCached(book_id)
    if cached then
        return cached
    end

    ensureDir()
    local path = CoverCache.pathFor(book_id)

    local ok, body = pcall(function()
        return client:get_binary(url, {
            accept = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            referer = "https://weread.qq.com/web/shelf",
        })
    end)
    if not ok or type(body) ~= "string" or #body == 0 then
        return nil, ok and "empty body" or tostring(body)
    end

    local bb = RenderImage:renderImageData(body, #body)
    if not bb then
        return nil, "render failed"
    end

    local f = io.open(path, "wb")
    if f then
        f:write(body)
        f:close()
    end

    return bb
end

--- Fetch cover bytes (prefer local cache, otherwise download).
function CoverCache.fetchBytes(client, book_id, url)
    if not client or not book_id or not url or url == "" then
        return nil, "missing args"
    end

    local cached = CoverCache.loadCachedBytes(book_id)
    if cached then
        return cached
    end

    local bb, err = CoverCache.fetch(client, book_id, url)
    if not bb then
        return nil, err
    end
    return CoverCache.loadCachedBytes(book_id)
end

--- Remove one book's cached cover thumbnail.
function CoverCache.clearBook(book_id)
    local path = CoverCache.pathFor(book_id)
    if not path then
        return true
    end
    if lfs.attributes(path, "mode") == "file" then
        os.remove(path)
        logger.info("weread cover: cleared book cover", book_id)
    end
    return true
end

--- Remove all cached cover thumbnails.
function CoverCache.clearAll()
    local files = select(1, countPath(CACHE_DIR))
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then
        return true, 0
    end
    local ok, err = pcall(function()
        ffiutil.purgeDir(CACHE_DIR)
    end)
    if not ok then
        logger.warn("weread cover: clearAll failed", err)
        return false, 0
    end
    logger.info("weread cover: cleared", files)
    return true, files
end

return CoverCache
