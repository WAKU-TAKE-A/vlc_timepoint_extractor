# VLC TimePoint Extractor

A VLC media player extension designed to manage video timepoints and automate frame sequence or clip extraction using FFmpeg.

This tool is particularly useful for technical engineers, researchers, and developers working on **computer vision datasets**, **visual inspection analysis**, or **video editing workflows**.

## Features

- **TimePoint Management**: Save specific timestamps with a structured naming convention (`Point0001`, `Point0002`, etc.).
- **Metadata Storage**: Automatically saves/loads data to a `.tp` file (Lua table format) in the same directory as the video file.
  - **Windows Unicode Path Fallback**: If the video path contains non-ASCII characters (e.g., Japanese) and saving next to the video fails, the `.tp` file is stored in VLC's user data directory under `timepoint_extractor/`.
- **Frame Extraction**: Export frame sequences with configurable FPS, resolution (width/height), and "before/after" temporal buffers.
- **Lossless Movie Cutting**: Instantly extract video segments using FFmpeg's stream copy (`-c copy`) without re-encoding.
- **Re-encode Export**: Encode video segments to apply specific resolution and FPS settings.
- **Remark Support**: Add custom notes/remarks to each timepoint for better data organization.
- **Safety & Stability**: Includes FFmpeg path verification and protected data loading (`pcall`) to prevent crashes.
- **Auto-Sorting**: Timepoints are always maintained in chronological order.
- **Windows Unicode Extraction Support**: On Windows, extraction is executed via a generated UTF-8 `.cmd` wrapper to improve compatibility with non-ASCII (e.g., Japanese) paths.

## Requirements

1. **VLC Media Player**: Tested on version 3.x.
2. **FFmpeg**: Must be installed and added to your system's **PATH** environment variable.

## Installation

1. Download the `timepoint_extractor.lua` script.
2. Move the script to the VLC extensions directory:
   - **Windows**: `C:\Program Files\VideoLAN\VLC\lua\extensions`
   - **Linux**: `~/.local/share/vlc/lua/extensions/`
3. Restart VLC.
4. Open the extension from the menu: `View` -> `VLC TimePoint Extractor`.

## Usage

### 1. Managing Points
- **Add TimePoint**: Captures the current video time and adds it to the list.
- **Update Remark**: Enter text in the Remark field and click this to update an existing point.
- **Jump To**: Select a point in the list to seek the video to that specific time. The remark will automatically populate the input field.
- **Remove**: Deletes the selected point and automatically re-labels remaining points to maintain the sequence.

### 2. Extraction
- **Extract Frames**: 
  - Creates a folder named `{video_name}_extracted_frames`.
  - Sub-folders are created for each point (e.g., `Point0001`).
  - Exports images as `.png` based on your FPS and resolution settings.
- **Extract Movie (Lossless)**: 
  - Creates a folder named `{video_name}_extracted_movies`.
  - Clips the video segment based on "Before" and "After" seconds using lossless stream copying.
  - Filename format: `PointXXXX_Remark.ext`.
- **Extract Movie (Encode)**:
  - Creates a folder named `{video_name}_extracted_movies`.
  - Re-encodes the segment to apply your resolution and FPS settings.
  - Filename format: `PointXXXX_Remark_encoded.ext`.

#### Notes (Windows extraction / logs)
On Windows, each extraction generates the following files under VLC user data directory `timepoint_extractor/`:
- `ffmpeg_last_command.txt` (last FFmpeg command; useful for copy/paste testing)
- `ffmpeg_run.cmd` (generated wrapper used to run FFmpeg; UTF-8 BOM + `chcp 65001`)
- `ffmpeg_last.log` (FFmpeg stdout/stderr output)

These files use **fixed names** and are **overwritten** each time you run an extraction.

## License
MIT License