--[[
-- VLC TimePoint Extractor
-- Concept: Manage video timepoints and extract frame sequences via FFmpeg.
-- Storage: Data is saved as a .tp file in the same directory as the video.
--]]

------------------------------------------------------------------------
-- Constants & Configuration
------------------------------------------------------------------------
local EXTENSION_VERSION = "0.9.0"
local APP_TITLE = "VLC TimePoint Extractor"
local TIMEPOINT_EXT = ".tp"
local TIME_BASE = 1000000 -- VLC internal time is in microseconds

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
local DIR_SUFFIX_FRAMES = "_frames"
local DIR_SUFFIX_CUTS = "_cuts"
local FALLBACK_VIDEO_NAME = "video"
local FALLBACK_EXTENSION = ".mp4"
local MOVIE_FILENAME_FORMAT = "%s_%s%s"

-- UI Layout Constants
local LIST_ROW_SPAN = 20

------------------------------------------------------------------------
-- Global State
------------------------------------------------------------------------
local state = {
    input = nil,
    media_uri = nil,
    tp_file_path = nil,
    timepoints = {},
    selected_id = nil,
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
        author = "UsWAKU-TAKE-A",
        shortdesc = APP_TITLE,
        description = "Manage TimePoints and extract frames to the video directory.",
        capabilities = {"menu", "input-listener"}
    }
end

------------------------------------------------------------------------
-- Activation / Deactivation
------------------------------------------------------------------------
function activate()
    vlc.msg.dbg("[TimePoint] Extension activated")
    initialize_state()
    load_timepoints()
    show_gui()
end

function deactivate()
    vlc.msg.dbg("[TimePoint] Extension deactivated")
    if state.ui.dialog then
        state.ui.dialog:hide()
    end
end

function close()
    vlc.deactivate()
end

function initialize_state()
    state.input = nil
    state.media_uri = nil
    state.tp_file_path = nil
    state.timepoints = {}
    state.selected_id = nil
end

------------------------------------------------------------------------
-- File I/O Logic (TimePoint Storage)
------------------------------------------------------------------------

function resolve_tp_path()
    local item = vlc.input.item()
    if not item then 
        vlc.msg.dbg("[TimePoint] No input item found.")
        return nil 
    end

    local uri = item:uri()
    local path = vlc.strings.make_path(uri)
    if not path then 
        vlc.msg.dbg("[TimePoint] Could not resolve local path from URI: " .. tostring(uri))
        return nil 
    end

    local base_path = path:match("(.+)%..+$") or path
    local target = base_path .. TIMEPOINT_EXT
    vlc.msg.dbg("[TimePoint] Resolved path: " .. target)
    return target
end

function save_timepoints()
    if not state.tp_file_path then
        state.tp_file_path = resolve_tp_path()
    end

    if not state.tp_file_path then
        vlc.msg.err("[TimePoint] Cannot save: Path is nil")
        if state.ui.widgets.status then
            state.ui.widgets.status:set_text("Error: Save path not found.")
        end
        return
    end
    
    vlc.msg.dbg("[TimePoint] Saving to: " .. state.tp_file_path)
    local file, err = io.open(state.tp_file_path, "wb")
    if err then
        vlc.msg.err("[TimePoint] Save failed: " .. tostring(err))
        if state.ui.widgets.status then
            state.ui.widgets.status:set_text("Save failed: " .. tostring(err))
        end
        return
    end

    file:write("return {\n")
    for _, tp in ipairs(state.timepoints) do
        file:write(string.format("  { time = %d, label = %q, formatted = %q, remark = %q },\n", 
            tp.time, tp.label, tp.formatted, tp.remark or ""))
    end
    file:write("}\n")
    file:close()
    vlc.msg.dbg("[TimePoint] Save successful.")
end

function load_timepoints()
    state.tp_file_path = resolve_tp_path()
    if not state.tp_file_path then 
        state.timepoints = {}
        return 
    end

    local chunk, err = loadfile(state.tp_file_path)
    if not err and chunk then
        local result = chunk()
        if type(result) == "table" then
            state.timepoints = result
        else
            state.timepoints = {}
        end
        vlc.msg.dbg("[TimePoint] Data loaded.")
    else
        vlc.msg.dbg("[TimePoint] No existing data or load error: " .. tostring(err))
        state.timepoints = {}
    end
end

------------------------------------------------------------------------
-- Utilities
------------------------------------------------------------------------
function format_time(micros)
    local total_seconds = math.floor(micros / TIME_BASE)
    local hours = math.floor(total_seconds / 3600)
    local minutes = math.floor((total_seconds % 3600) / 60)
    local seconds = total_seconds % 60
    local millis = math.floor((micros % TIME_BASE) / 1000)
    return string.format("%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
end

function sanitize_filename(name)
    local s = tostring(name or "")
    if s == "" then return "noname" end
    s = s:gsub("[%s%c\\/:%*%?\"<>|]", "_")
    return s
end

function update_timepoints_order()
    table.sort(state.timepoints, function(a, b) return a.time < b.time end)
    for i, tp in ipairs(state.timepoints) do
        tp.label = string.format(POINT_LABEL_FORMAT, i)
    end
end

------------------------------------------------------------------------
-- GUI Logic
------------------------------------------------------------------------
function show_gui()
    if state.ui.dialog then
        state.ui.dialog:delete()
    end

    state.ui.dialog = vlc.dialog(APP_TITLE)
    local d = state.ui.dialog

    -- Top Section: Add/Edit Remark
    d:add_button("Add TimePoint", handle_add, 1, 1, 1, 1)
    d:add_label("Remark:", 2, 1, 1, 1)
    state.ui.widgets.remark_input = d:add_text_input("", 3, 1, 1, 1)

    -- Middle Section: List and Controls
    state.ui.widgets.tp_list = d:add_list(2, 2, 2, LIST_ROW_SPAN)
    d:add_button("Remove TimePoint", handle_remove, 1, 2, 1, 1)
    d:add_button("Jump To", handle_jump, 1, 3, 1, 1)
    d:add_button("Update Remark", handle_update, 1, 4, 1, 1)

    -- Extraction Settings
    local row = 6
    d:add_label("<b>Extraction Settings</b>", 1, row, 1, 1)
    
    row = row + 1
    d:add_label("Before (sec):", 1, row, 1, 1)
    state.ui.widgets.ext_before = d:add_text_input(tostring(DEFAULT_BEFORE_SEC), 1, row + 1, 1, 1)
    
    row = row + 2
    d:add_label("After (sec):", 1, row, 1, 1)
    state.ui.widgets.ext_after = d:add_text_input(tostring(DEFAULT_AFTER_SEC), 1, row + 1, 1, 1)

    row = row + 2
    d:add_label("FPS:", 1, row, 1, 1)
    state.ui.widgets.ext_fps = d:add_text_input(tostring(DEFAULT_FPS), 1, row + 1, 1, 1)

    row = row + 2
    d:add_label("Resolution (WxH):", 1, row, 1, 1)
    state.ui.widgets.ext_w = d:add_text_input(tostring(DEFAULT_WIDTH), 1, row + 1, 1, 1)
    state.ui.widgets.ext_h = d:add_text_input(tostring(DEFAULT_HEIGHT), 1, row + 2, 1, 1)

    row = row + 3
    d:add_button("Extract Frames", handle_extract, 1, row, 1, 1)
    row = row + 1
    d:add_button("Extract Movie", handle_extract_movie, 1, row, 1, 1)
    
    row = row + 1
    d:add_button("Close", close, 1, row + 1, 1, 1)

    state.ui.widgets.status = d:add_label("", 2, LIST_ROW_SPAN + 2, 1, 1)

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
-- Button Handlers
------------------------------------------------------------------------
function handle_add()
    local input_obj = vlc.object.input()
    if not input_obj then 
        state.ui.widgets.status:set_text("Error: No active video.")
        return 
    end

    local currentTime = vlc.var.get(input_obj, "time")
    local remark = state.ui.widgets.remark_input:get_text()

    table.insert(state.timepoints, {
        time = currentTime,
        label = "",
        formatted = format_time(currentTime),
        remark = remark
    })

    update_timepoints_order()
    save_timepoints()
    refresh_list()
    state.ui.widgets.status:set_text("TimePoint added.")
end

function handle_jump()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection then return end
    
    local id = next(selection)
    if id then
        local input_obj = vlc.object.input()
        if input_obj then
            vlc.var.set(input_obj, "time", state.timepoints[id].time)
        end
    end
end

function handle_update()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection then return end
    
    local id = next(selection)
    local new_remark = state.ui.widgets.remark_input:get_text()
    if id then
        state.timepoints[id].remark = new_remark
        save_timepoints()
        refresh_list()
        state.ui.widgets.status:set_text("Remark updated.")
    end
end

function handle_remove()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection then return end
    
    local id = next(selection)
    if id then
        table.remove(state.timepoints, id)
        update_timepoints_order()
        save_timepoints()
        refresh_list()
        state.ui.widgets.status:set_text("TimePoint removed.")
    end
end

------------------------------------------------------------------------
-- FFmpeg Extraction Logic
------------------------------------------------------------------------
function handle_extract()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection then
        state.ui.widgets.status:set_text("Select a TimePoint first.")
        return
    end

    local id = next(selection)
    local tp = state.timepoints[id]
    
    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local aft = tonumber(state.ui.widgets.ext_after:get_text()) or 0
    local fps = tonumber(state.ui.widgets.ext_fps:get_text()) or 1
    local w   = tonumber(state.ui.widgets.ext_w:get_text()) or DEFAULT_WIDTH
    local h   = tonumber(state.ui.widgets.ext_h:get_text()) or DEFAULT_HEIGHT

    local item = vlc.input.item()
    if not item then return end
    
    local video_path = vlc.strings.make_path(item:uri())
    if not video_path then return end
    
    local video_dir = video_path:match("^(.*[\\/])")
    local video_name = video_path:match("([^\\/]+)%.%w+$") or FALLBACK_VIDEO_NAME
    
    local slash = package.config:sub(1,1)
    local export_dir_name = video_name .. DIR_SUFFIX_FRAMES
    local sub_dir_name = sanitize_filename(tp.label)
    local full_export_path = video_dir .. export_dir_name .. slash .. sub_dir_name

    vlc.io.mkdir(video_dir .. export_dir_name, "0700")
    vlc.io.mkdir(full_export_path, "0700")

    local start_sec = math.max(0, (tp.time / TIME_BASE) - bef)
    local duration = bef + aft
    local output_pattern = full_export_path .. slash .. "frame_%04d.png"
    
    local cmd
    if duration > 0 then
        cmd = string.format('ffmpeg -y -ss %.3f -t %.3f -i "%s" -vf "fps=%d,scale=%d:%d" "%s"',
            start_sec, duration, video_path, fps, w, h, output_pattern)
    else
        cmd = string.format('ffmpeg -y -ss %.3f -i "%s" -frames:v 1 -vf "scale=%d:%d" "%s"',
            start_sec, video_path, w, h, output_pattern)
    end

    state.ui.widgets.status:set_text("Extracting frames...")
    local platform_cmd = (slash == "\\") and ('start /b ' .. cmd) or (cmd .. ' &')
    os.execute(platform_cmd)
end

function handle_extract_movie()
    local selection = state.ui.widgets.tp_list:get_selection()
    if not selection then
        state.ui.widgets.status:set_text("Select a TimePoint first.")
        return
    end

    local id = next(selection)
    local tp = state.timepoints[id]

    local bef = tonumber(state.ui.widgets.ext_before:get_text()) or 0
    local aft = tonumber(state.ui.widgets.ext_after:get_text()) or 0
    local duration = bef + aft

    if duration <= 0 then
        state.ui.widgets.status:set_text("Error: Before + After must be > 0.")
        return
    end

    local item = vlc.input.item()
    if not item then return end
    
    local video_path = vlc.strings.make_path(item:uri())
    if not video_path then return end
    
    local video_dir = video_path:match("^(.*[\\/])")
    local video_name = video_path:match("([^\\/]+)%.%w+$") or FALLBACK_VIDEO_NAME
    local extension = video_path:match("(%.%w+)$") or FALLBACK_EXTENSION
    
    local slash = package.config:sub(1,1)
    local export_dir_name = video_name .. DIR_SUFFIX_CUTS
    local full_export_path = video_dir .. export_dir_name

    vlc.io.mkdir(full_export_path, "0700")

    local start_sec = math.max(0, (tp.time / TIME_BASE) - bef)
    local output_filename = string.format(MOVIE_FILENAME_FORMAT, 
        sanitize_filename(tp.label), 
        sanitize_filename(tp.remark), 
        extension)
    local output_path = full_export_path .. slash .. output_filename

    -- -ssを-iの前に置くことで高速にシークし、-c copyで無劣化抽出
    local cmd = string.format('ffmpeg -y -ss %.3f -t %.3f -i "%s" -c copy "%s"',
        start_sec, duration, video_path, output_path)

    state.ui.widgets.status:set_text("Extracting movie...")
    local platform_cmd = (slash == "\\") and ('start /b ' .. cmd) or (cmd .. ' &')
    os.execute(platform_cmd)
end

------------------------------------------------------------------------
-- VLC Event Listeners
------------------------------------------------------------------------
function input_changed()
    initialize_state()
    load_timepoints()
    if state.ui.dialog then
        refresh_list()
    end
end

function menu()
    return {"Open TimePoint Extractor"}
end

function trigger_menu()
    show_gui()
end