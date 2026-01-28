--[[
-- VLC TimePoint Extractor
-- Concept: Manage video timepoints and extract frame sequences via FFmpeg.
-- Storage: Data is saved as a .tp file in the same directory as the video.
--   Windows: if preferred path has non-ASCII bytes -> force fallback to userdatadir (avoid mojibake)
-- Version: 0.9.8
--]]

------------------------------------------------------------------------
-- Constants & Configuration
------------------------------------------------------------------------
local EXTENSION_VERSION = "0.9.8"
local APP_TITLE = "VLC TimePoint Extractor"
local TIMEPOINT_EXT = ".tp"
local TIME_BASE = 1000000 

-- Point Label Settings
local POINT_LABEL_PREFIX = "Point"
local POINT_LABEL_FORMAT = POINT_LABEL_PREFIX .. "%04d"

-- Default Extraction Settings
local DEFAULT_WIDTH = 640
local DEFAULT_HEIGHT = 480
local DEFAULT_FPS = 5
local DEFAULT_BEFORE_SEC = 0
local DEFAULT_AFTER_SEC = 0

-- Directory & File Naming Constants
local DIR_SUFFIX_FRAMES = "_extracted_frames"
local DIR_SUFFIX_CUTS = "_extracted_movies"
local FALLBACK_VIDEO_NAME = "video"
local FALLBACK_EXTENSION = ".mp4"
local MOVIE_FILENAME_SEPARATOR = "_"

local TP_FALLBACK_SUBDIR = "timepoint_extractor"
local TP_FALLBACK_KEY_MAXLEN = 120

local FFLOG_NAME = "ffmpeg_last.log"
local FFCMDTXT_NAME = "ffmpeg_last_command.txt"
local FFRUN_NAME = "ffmpeg_run.cmd"

------------------------------------------------------------------------
-- Global State
------------------------------------------------------------------------
local state = {
    media_uri = nil,
    tp_file_path = nil,
    timepoints = {},
    ffmpeg_available = false,
    ui = {
        dialog = nil,
        widgets = {}
    }
}

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function get_slash() return package.config:sub(1,1) end
local function is_windows() return get_slash() == "\\" end
local function has_non_ascii_bytes(s) return (type(s) == "string") and (s:find("[\128-\255]") ~= nil) end

local function trim_trailing_slash(p)
    if not p or p == "" then return p end
    if p:sub(-1) == "/" or p:sub(-1) == "\\" then return p:sub(1, -2) end
    return p
end

local function path_join(dir, leaf)
    local slash = get_slash()
    dir  = tostring(dir or ""):gsub("[/\\]+$", "")
    leaf = tostring(leaf or ""):gsub("^[/\\]+", "")
    return dir .. slash .. leaf
end

local function write_text_file(path, text, with_utf8_bom)
    if not path then return false end
    local f = io.open(path, "wb")
    if not f then return false end
    if with_utf8_bom then f:write("\239\187\191") end -- UTF-8 BOM
    f:write(text or "")
    f:close()
    return true
end

------------------------------------------------------------------------
-- VLC Extension Descriptor
------------------------------------------------------------------------
function descriptor()
    return {
        title = APP_TITLE .. " " .. EXTENSION_VERSION,
        version = EXTENSION_VERSION,
        author = "WAKU-TAKE-A",
        shortdesc = APP_TITLE,
        description = "Manage TimePoints and extract frames/clips. Includes Lossless and Encode options.",
        capabilities = {"menu", "input-listener"}
    }
end

------------------------------------------------------------------------
-- Activation / Deactivation
------------------------------------------------------------------------
function activate()
    initialize_state()
    check_ffmpeg()
    sync_with_input()
    show_gui()
end

function deactivate()
    if state.ui.dialog then state.ui.dialog:hide() end
end

function close() vlc.deactivate() end

function initialize_state()
    state.media_uri = nil
    state.tp_file_path = nil
    state.timepoints = {}
end

------------------------------------------------------------------------
-- Core Sync Logic
------------------------------------------------------------------------
function sync_with_input()
    local item = vlc.input.item()
    if not item then return end
    local current_uri = item:uri()
    if state.media_uri ~= current_uri then
        state.media_uri = current_uri
        load_timepoints()
        if state.ui.dialog then refresh_list() end
    end
end

function check_ffmpeg()
    local dev_null = is_windows() and "NUL" or "/dev/null"
    local cmd = string.format("ffmpeg -version > %s 2>&1", dev_null)
    local success = os.execute(cmd)
    state.ffmpeg_available = (success == 0 or success == true)
    return state.ffmpeg_available
end

------------------------------------------------------------------------
-- Utilities
------------------------------------------------------------------------
function format_time(micros)
    local total_seconds = math.floor(micros / TIME_BASE)
    local h = math.floor(total_seconds / 3600)
    local m = math.floor((total_seconds % 3600) / 60)
    local s = total_seconds % 60
    local ms = math.floor((micros % TIME_BASE) / 1000)
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

function sanitize_filename(name)
    local s = tostring(name or ""):gsub("[%s%c\\/:%*%?\"<>|]", "_")
    return s:gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function djb2_hash(str)
    local h = 5381
    for i = 1, #str do
        h = ((h * 33) + str:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

function update_timepoints_order()
    table.sort(state.timepoints, function(a, b) return a.time < b.time end)
    for i, tp in ipairs(state.timepoints) do
        tp.label = string.format(POINT_LABEL_FORMAT, i)
    end
end

function update_status(msg)
    if state.ui.widgets.status then state.ui.widgets.status:set_text(msg) end
end

------------------------------------------------------------------------
-- userdatadir helpers (tp + ffmpeg logs)
------------------------------------------------------------------------
local function get_tp_fallback_dir()
    if not vlc.config or not vlc.config.userdatadir then return nil end
    local base = trim_trailing_slash(vlc.config.userdatadir())
    if not base or base == "" then return nil end
    local dir = base .. get_slash() .. TP_FALLBACK_SUBDIR
    if vlc.io and vlc.io.mkdir then vlc.io.mkdir(dir, "0700") end
    return dir
end

local function get_ffmpeg_log_path()
    local dir = get_tp_fallback_dir()
    if not dir then return nil end
    return path_join(dir, FFLOG_NAME)
end

local function get_ffmpeg_cmdtxt_path()
    local dir = get_tp_fallback_dir()
    if not dir then return nil end
    return path_join(dir, FFCMDTXT_NAME)
end

local function get_ffmpeg_run_cmd_path()
    local dir = get_tp_fallback_dir()
    if not dir then return nil end
    return path_join(dir, FFRUN_NAME)
end

------------------------------------------------------------------------
-- Media context / local path
------------------------------------------------------------------------
local function get_media_item()
    return vlc.input.item()
end

local function get_input_path_for_ffmpeg()
    -- IMPORTANT: use local path (not file:/// URI)
    local item = get_media_item()
    if not item then return nil end
    local p = vlc.strings.make_path(item:uri())
    if p and p ~= "" then return p end
    return nil
end

------------------------------------------------------------------------
-- Windows ffmpeg runner (.cmd wrapper)
------------------------------------------------------------------------
local function save_last_ffmpeg_command(cmd_plain)
    write_text_file(get_ffmpeg_cmdtxt_path(), (cmd_plain or "") .. "\r\n", false)
end

local function run_ffmpeg_async(cmd_plain)
    save_last_ffmpeg_command(cmd_plain)

    local log_path = get_ffmpeg_log_path()
    local run_cmd_path = get_ffmpeg_run_cmd_path()

    if is_windows() then
        local log_redir = ""
        if log_path then
            log_redir = string.format(' > "%s" 2>&1', log_path)
        end

        -- IMPORTANT:
        -- In .cmd, %0..%9 are replaced by batch args. So frame_%04d.png breaks.
        -- Escape % as %% only for the cmd file content.
        local cmd_for_cmdfile = (cmd_plain or ""):gsub("%%", "%%%%")

        local script = table.concat({
            "@echo off",
            "setlocal",
            "chcp 65001 >nul",
            cmd_for_cmdfile .. log_redir,
            "endlocal",
            ""
        }, "\r\n")

        -- UTF-8 BOM付きで書く（日本語パスを.cmd内にそのまま書ける可能性を上げる）
        write_text_file(run_cmd_path, script, true)

        -- 実行（バックグラウンド）
        os.execute(string.format('start "" /b cmd /v:off /c "%s"', run_cmd_path))
    else
        local final = cmd_plain
        if log_path then
            final = final .. string.format(' > "%s" 2>&1', log_path)
        end
        os.execute(final .. " &")
    end
end

------------------------------------------------------------------------
-- TP Path Resolve (preferred + fallback)
------------------------------------------------------------------------
local function resolve_tp_paths()
    local item = get_media_item()
    if not item then return nil, nil end

    local preferred = nil
    local path = vlc.strings.make_path(item:uri())
    if path then
        preferred = (path:match("(.+)%..+$") or path) .. TIMEPOINT_EXT
    end

    local fallback = nil
    local fdir = get_tp_fallback_dir()
    if fdir then
        local uri = item:uri() or ""
        local key = sanitize_filename(uri)
        if #key > TP_FALLBACK_KEY_MAXLEN then
            key = key:sub(1, TP_FALLBACK_KEY_MAXLEN) .. "_" .. djb2_hash(uri)
        end
        fallback = fdir .. get_slash() .. key .. TIMEPOINT_EXT
    end

    return preferred, fallback
end

local function force_fallback_for_preferred(preferred_path)
    return is_windows() and has_non_ascii_bytes(preferred_path)
end

------------------------------------------------------------------------
-- File I/O (.tp)
------------------------------------------------------------------------
local function write_timepoints_to_file(fh)
    fh:write("return {\n")
    for _, tp in ipairs(state.timepoints) do
        fh:write(string.format(
            "  { time = %d, label = %q, formatted = %q, remark = %q },\n",
            tp.time, tp.label, tp.formatted, tp.remark or ""
        ))
    end
    fh:write("}\n")
end

local function try_save_to(path)
    if not path then return false end
    local fh = io.open(path, "wb")
    if not fh then return false end
    write_timepoints_to_file(fh)
    fh:close()
    state.tp_file_path = path
    return true
end

function save_timepoints()
    local preferred, fallback = resolve_tp_paths()

    if force_fallback_for_preferred(preferred) then
        if try_save_to(fallback) then
            update_status("TP saved in userdatadir (forced fallback).")
        else
            update_status("Failed to save TP file (fallback).")
        end
        return
    end

    if try_save_to(preferred) then return end
    if try_save_to(fallback) then
        update_status("TP saved in userdatadir (fallback).")
        return
    end
    update_status("Failed to save TP file.")
end

local function try_load_timepoints(path)
    if not path then return nil end
    local chunk = loadfile(path)
    if not chunk then return nil end
    local ok, result = pcall(chunk)
    if ok and type(result) == "table" then return result end
    return nil
end

function load_timepoints()
    local preferred, fallback = resolve_tp_paths()

    if force_fallback_for_preferred(preferred) then
        local t = try_load_timepoints(fallback)
        if t then
            state.tp_file_path = fallback
            state.timepoints = t
            update_status("TP loaded from userdatadir (forced fallback).")
            return
        end
        state.tp_file_path = fallback
        state.timepoints = {}
        return
    end

    local t = try_load_timepoints(preferred)
    if t then
        state.tp_file_path = preferred
        state.timepoints = t
        return
    end

    t = try_load_timepoints(fallback)
    if t then
        state.tp_file_path = fallback
        state.timepoints = t
        update_status("TP loaded from userdatadir (fallback).")
        return
    end

    state.tp_file_path = preferred or fallback
    state.timepoints = {}
end

------------------------------------------------------------------------
-- GUI Setup
------------------------------------------------------------------------
function show_gui()
    if state.ui.dialog then state.ui.dialog:delete() end
    state.ui.dialog = vlc.dialog(APP_TITLE)
    local d = state.ui.dialog

    -- Row 1: Operations Header
    d:add_button("Add TimePoint", handle_add, 1, 1, 1, 1)
    d:add_label("Remark:", 2, 1, 1, 1)
    state.ui.widgets.remark_input = d:add_text_input("", 3, 1, 1, 1)

    -- Right Section: List (Rows 2 to 18)
    state.ui.widgets.tp_list = d:add_list(2, 2, 2, 17)

    -- Left Section: Point Operations (Rows 2 - 4)
    d:add_button("Remove Point", handle_remove, 1, 2, 1, 1)
    d:add_button("Jump To", handle_jump, 1, 3, 1, 1)
    d:add_button("Update Remark", handle_update, 1, 4, 1, 1)

    -- Left Section: Extraction Settings (Sequential from Row 5)
    d:add_label("<b>Extraction Settings</b>", 1, 5, 1, 1)
    d:add_label("Before (sec):", 1, 6, 1, 1)
    state.ui.widgets.ext_before = d:add_text_input(tostring(DEFAULT_BEFORE_SEC), 1, 7, 1, 1)
    d:add_label("After (sec):", 1, 8, 1, 1)
    state.ui.widgets.ext_after = d:add_text_input(tostring(DEFAULT_AFTER_SEC), 1, 9, 1, 1)
    d:add_label("FPS:", 1, 10, 1, 1)
    state.ui.widgets.ext_fps = d:add_text_input(tostring(DEFAULT_FPS), 1, 11, 1, 1)
    d:add_label("Resolution (WxH):", 1, 12, 1, 1)
    state.ui.widgets.ext_w = d:add_text_input(tostring(DEFAULT_WIDTH), 1, 13, 1, 1)
    state.ui.widgets.ext_h = d:add_text_input(tostring(DEFAULT_HEIGHT), 1, 14, 1, 1)

    -- Action Buttons (Rows 15 - 18)
    d:add_button("Extract Frames", handle_extract, 1, 15, 1, 1)
    d:add_button("Extract Movie (Lossless)", handle_extract_movie, 1, 16, 1, 1)
    d:add_button("Extract Movie (Encode)", handle_extract_movie_encode, 1, 17, 1, 1)
    d:add_button("Close", close, 1, 18, 1, 1)

    -- Status Label
    state.ui.widgets.status = d:add_label("", 2, 19, 2, 1)

    if not state.ffmpeg_available then
        update_status("<font color='red'>FFmpeg not found in PATH</font>")
    end
    refresh_list()
end

function refresh_list()
    if not state.ui.widgets.tp_list then return end
    state.ui.widgets.tp_list:clear()
    for i, tp in ipairs(state.timepoints) do
        local display = string.format("[%s] %s %s", tp.formatted, tp.label, tp.remark or "")
        state.ui.widgets.tp_list:add_value(display, i)
    end
end

------------------------------------------------------------------------
-- Handlers
------------------------------------------------------------------------
function handle_add()
    sync_with_input()
    local input_obj = vlc.object.input()
    if not input_obj then return end
    local micros = vlc.var.get(input_obj, "time")
    table.insert(state.timepoints, {
        time = micros, label = "", formatted = format_time(micros),
        remark = state.ui.widgets.remark_input:get_text()
    })
    update_timepoints_order()
    save_timepoints()
    refresh_list()
end

function handle_jump()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.")
        return 
    end
    local id = next(selection)
    local input_obj = vlc.object.input()
    if id and input_obj then
        vlc.var.set(input_obj, "time", state.timepoints[id].time)
        state.ui.widgets.remark_input:set_text(state.timepoints[id].remark or "")
    end
end

function handle_update()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.")
        return 
    end
    local id = next(selection)
    if id then
        state.timepoints[id].remark = state.ui.widgets.remark_input:get_text()
        save_timepoints()
        refresh_list()
        update_status("Remark updated.")
    end
end

function handle_remove()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.")
        return 
    end
    local id = next(selection)
    if id then
        table.remove(state.timepoints, id)
        update_timepoints_order()
        save_timepoints()
        refresh_list()
        update_status("TimePoint removed.")
    end
end

------------------------------------------------------------------------
-- FFmpeg Logic
------------------------------------------------------------------------
function get_export_context()
    local item = get_media_item()
    if not item then return nil end
    local path = vlc.strings.make_path(item:uri())
    if not path then return nil end
    return path,
        path:match("^(.*[\\/])"),
        path:match("([^\\/]+)%.%w+$") or FALLBACK_VIDEO_NAME,
        path:match("(%.%w+)$") or FALLBACK_EXTENSION
end

function handle_extract()
    if not check_ffmpeg() then update_status("FFmpeg not found.") return end
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point.") return end
    
    local tp = state.timepoints[next(selection)]
    local v_path, v_dir, v_name = get_export_context()
    if not v_path then update_status("No input.") return end

    local root = v_dir .. v_name .. DIR_SUFFIX_FRAMES
    local sub  = path_join(root, sanitize_filename(tp.label))
    vlc.io.mkdir(root, "0700"); vlc.io.mkdir(sub, "0700")

    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local dur = bef + (tonumber(state.ui.widgets.ext_after:get_text()) or 0)
    local start = math.max(0, (tp.time / TIME_BASE) - bef)

    local in_path = get_input_path_for_ffmpeg() or v_path
    local out_pattern = path_join(sub, "frame_%04d.png")
    local out_single  = path_join(sub, "frame_0001.png")

    local cmd
    if dur > 0 then
        cmd = string.format(
            'ffmpeg -y -ss %.3f -t %.3f -i "%s" -vf "fps=%d,scale=%d:%d" "%s"',
            start, dur, in_path,
            tonumber(state.ui.widgets.ext_fps:get_text()) or 1,
            tonumber(state.ui.widgets.ext_w:get_text()) or DEFAULT_WIDTH,
            tonumber(state.ui.widgets.ext_h:get_text()) or DEFAULT_HEIGHT,
            out_pattern
        )
    else
        cmd = string.format(
            'ffmpeg -y -ss %.3f -i "%s" -frames:v 1 -vf "scale=%d:%d" "%s"',
            start, in_path,
            tonumber(state.ui.widgets.ext_w:get_text()) or DEFAULT_WIDTH,
            tonumber(state.ui.widgets.ext_h:get_text()) or DEFAULT_HEIGHT,
            out_single
        )
    end

    update_status("Extracting frames... (see ffmpeg_last.log / ffmpeg_run.cmd in userdatadir)")
    run_ffmpeg_async(cmd)
end

function handle_extract_movie()
    if not check_ffmpeg() then update_status("FFmpeg not found.") return end
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.") return end
    
    local tp = state.timepoints[next(selection)]
    local v_path, v_dir, v_name, v_ext = get_export_context()
    if not v_path then update_status("No input.") return end

    local export_dir = v_dir .. v_name .. DIR_SUFFIX_CUTS
    vlc.io.mkdir(export_dir, "0700")
    
    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local dur = bef + (tonumber(state.ui.widgets.ext_after:get_text()) or 0)

    local out_name = tp.label
        .. (tp.remark ~= "" and (MOVIE_FILENAME_SEPARATOR .. sanitize_filename(tp.remark)) or "")
        .. v_ext

    local in_path = get_input_path_for_ffmpeg() or v_path
    local out_path = path_join(export_dir, out_name)

    local cmd = string.format(
        'ffmpeg -y -ss %.3f -t %.3f -i "%s" -c copy "%s"',
        math.max(0, (tp.time / TIME_BASE) - bef), dur, in_path, out_path
    )

    update_status("Extracting movie (Lossless)... (see ffmpeg_last.log / ffmpeg_run.cmd in userdatadir)")
    run_ffmpeg_async(cmd)
end

function handle_extract_movie_encode()
    if not check_ffmpeg() then update_status("FFmpeg not found.") return end
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.") return end
    
    local tp = state.timepoints[next(selection)]
    local v_path, v_dir, v_name, v_ext = get_export_context()
    if not v_path then update_status("No input.") return end

    local export_dir = v_dir .. v_name .. DIR_SUFFIX_CUTS
    vlc.io.mkdir(export_dir, "0700")
    
    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local dur = bef + (tonumber(state.ui.widgets.ext_after:get_text()) or 0)
    local fps = tonumber(state.ui.widgets.ext_fps:get_text()) or 30
    local w   = tonumber(state.ui.widgets.ext_w:get_text()) or DEFAULT_WIDTH
    local h   = tonumber(state.ui.widgets.ext_h:get_text()) or DEFAULT_HEIGHT

    local out_name = tp.label
        .. (tp.remark ~= "" and (MOVIE_FILENAME_SEPARATOR .. sanitize_filename(tp.remark)) or "")
        .. "_encoded"
        .. v_ext

    local in_path = get_input_path_for_ffmpeg() or v_path
    local out_path = path_join(export_dir, out_name)

    local cmd = string.format(
        'ffmpeg -y -ss %.3f -t %.3f -i "%s" -vf "fps=%d,scale=%d:%d" -c:v libx264 -preset ultrafast -crf 23 -c:a aac "%s"',
        math.max(0, (tp.time / TIME_BASE) - bef), dur, in_path, fps, w, h, out_path
    )

    update_status("Extracting movie (Encoding)... (see ffmpeg_last.log / ffmpeg_run.cmd in userdatadir)")
    run_ffmpeg_async(cmd)
end

function input_changed() sync_with_input() end
function menu() return {"Open TimePoint Extractor"} end
function trigger_menu() show_gui() end