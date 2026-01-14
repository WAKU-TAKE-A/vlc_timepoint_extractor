--[[
-- VLC TimePoint Extractor
-- Concept: Manage video timepoints and extract frame sequences via FFmpeg.
-- Storage: Data is saved as a .tp file in the same directory as the video.
-- Version: 0.9.6 (Fixed selection check logic and author name)
--]]

------------------------------------------------------------------------
-- Constants & Configuration
------------------------------------------------------------------------
local EXTENSION_VERSION = "0.9.6"
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
-- VLC Extension Descriptor
------------------------------------------------------------------------
function descriptor()
    return {
        title = APP_TITLE .. " " .. EXTENSION_VERSION,
        version = EXTENSION_VERSION,
        author = "WAKU-TAKE-A",
        shortdesc = APP_TITLE,
        description = "Manage TimePoints and extract frames/clips. Robust selection check version.",
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
    local slash = package.config:sub(1,1)
    local dev_null = (slash == "\\") and "NUL" or "/dev/null"
    local cmd = string.format("ffmpeg -version > %s 2>&1", dev_null)
    local success = os.execute(cmd)
    state.ffmpeg_available = (success == 0)
    return state.ffmpeg_available
end

------------------------------------------------------------------------
-- File I/O
------------------------------------------------------------------------
function resolve_tp_path()
    local item = vlc.input.item()
    if not item then return nil end
    local path = vlc.strings.make_path(item:uri())
    if not path then return nil end
    return (path:match("(.+)%..+$") or path) .. TIMEPOINT_EXT
end

function save_timepoints()
    state.tp_file_path = resolve_tp_path()
    if not state.tp_file_path then return end
    local file, err = io.open(state.tp_file_path, "wb")
    if err then return end
    file:write("return {\n")
    for _, tp in ipairs(state.timepoints) do
        file:write(string.format("  { time = %d, label = %q, formatted = %q, remark = %q },\n", 
            tp.time, tp.label, tp.formatted, tp.remark or ""))
    end
    file:write("}\n")
    file:close()
end

function load_timepoints()
    state.tp_file_path = resolve_tp_path()
    if not state.tp_file_path then 
        state.timepoints = {}
        return 
    end
    local chunk, load_err = loadfile(state.tp_file_path)
    if not load_err and chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            state.timepoints = result
            return
        end
    end
    state.timepoints = {}
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
-- GUI Setup
------------------------------------------------------------------------
function show_gui()
    if state.ui.dialog then state.ui.dialog:delete() end
    state.ui.dialog = vlc.dialog(APP_TITLE)
    local d = state.ui.dialog

    d:add_button("Add TimePoint", handle_add, 1, 1, 1, 1)
    d:add_label("Remark:", 2, 1, 1, 1)
    state.ui.widgets.remark_input = d:add_text_input("", 3, 1, 1, 1)

    state.ui.widgets.tp_list = d:add_list(2, 2, 2, 16)

    d:add_button("Remove Point", handle_remove, 1, 2, 1, 1)
    d:add_button("Jump To", handle_jump, 1, 3, 1, 1)
    d:add_button("Update Remark", handle_update, 1, 4, 1, 1)

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

    d:add_button("Extract Frames", handle_extract, 1, 15, 1, 1)
    d:add_button("Extract Movie", handle_extract_movie, 1, 16, 1, 1)
    d:add_button("Close", close, 1, 17, 1, 1)

    state.ui.widgets.status = d:add_label("", 2, 18, 2, 1)

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
    update_status("TimePoint added.")
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
-- Extraction
------------------------------------------------------------------------
function get_export_context()
    local item = vlc.input.item()
    if not item then return nil end
    local path = vlc.strings.make_path(item:uri())
    if not path then return nil end
    return path, path:match("^(.*[\\/])"), path:match("([^\\/]+)%.%w+$") or FALLBACK_VIDEO_NAME, path:match("(%.%w+)$") or FALLBACK_EXTENSION
end

function handle_extract()
    if not check_ffmpeg() then update_status("FFmpeg not found.") return end
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.")
        return 
    end
    local tp = state.timepoints[next(selection)]
    local v_path, v_dir, v_name = get_export_context()
    local slash = package.config:sub(1,1)
    local frame_dir = v_dir .. v_name .. DIR_SUFFIX_FRAMES
    local sub_dir = frame_dir .. slash .. sanitize_filename(tp.label)
    vlc.io.mkdir(frame_dir, "0700")
    vlc.io.mkdir(sub_dir, "0700")
    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local dur = bef + (tonumber(state.ui.widgets.ext_after:get_text()) or 0)
    local start = math.max(0, (tp.time / TIME_BASE) - bef)
    local cmd
    if dur > 0 then
        cmd = string.format('ffmpeg -y -ss %.3f -t %.3f -i "%s" -vf "fps=%d,scale=%d:%d" "%s/frame_%%04d.png"',
            start, dur, v_path, tonumber(state.ui.widgets.ext_fps:get_text()) or 1,
            tonumber(state.ui.widgets.ext_w:get_text()) or DEFAULT_WIDTH,
            tonumber(state.ui.widgets.ext_h:get_text()) or DEFAULT_HEIGHT, sub_dir)
    else
        cmd = string.format('ffmpeg -y -ss %.3f -i "%s" -frames:v 1 -vf "scale=%d:%d" "%s/frame_0001.png"',
            start, v_path, tonumber(state.ui.widgets.ext_w:get_text()) or DEFAULT_WIDTH,
            tonumber(state.ui.widgets.ext_h:get_text()) or DEFAULT_HEIGHT, sub_dir)
    end
    update_status("Extracting frames...")
    os.execute((slash == "\\") and ('start /b ' .. cmd) or (cmd .. ' &'))
end

function handle_extract_movie()
    if not check_ffmpeg() then update_status("FFmpeg not found.") return end
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection or next(selection) == nil then 
        update_status("Select a point first.")
        return 
    end
    local tp = state.timepoints[next(selection)]
    local v_path, v_dir, v_name, v_ext = get_export_context()
    local slash = package.config:sub(1,1)
    local export_dir = v_dir .. v_name .. DIR_SUFFIX_CUTS
    vlc.io.mkdir(export_dir, "0700")
    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local dur = bef + (tonumber(state.ui.widgets.ext_after:get_text()) or 0)
    local out_name = tp.label .. (tp.remark ~= "" and (MOVIE_FILENAME_SEPARATOR .. sanitize_filename(tp.remark)) or "") .. v_ext
    local cmd = string.format('ffmpeg -y -ss %.3f -t %.3f -i "%s" -c copy "%s/%s"',
        math.max(0, (tp.time / TIME_BASE) - bef), dur, v_path, export_dir, out_name)
    update_status("Extracting movie...")
    os.execute((slash == "\\") and ('start /b ' .. cmd) or (cmd .. ' &'))
end

function input_changed() sync_with_input() end
function menu() return {"Open TimePoint Extractor"} end
function trigger_menu() show_gui() end
