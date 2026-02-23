# VLC TimePoint Extractor

A VLC media player extension for managing video timepoints and automating frame sequence or clip extraction using FFmpeg.

Particularly useful for technical engineers, researchers, and developers working on **computer vision datasets**, **visual inspection analysis**, or **video editing workflows**.

---

## Features

- **TimePoint Management**: Save specific timestamps with a structured naming convention (`Point0001`, `Point0002`, etc.).
- **Metadata Storage**: Automatically saves and loads data to a `.tp` file in the same directory as the video file.
  - **Windows Unicode Path Fallback**: If the video path contains non-ASCII characters (e.g., Japanese), the `.tp` file is stored in VLC's user data directory under `timepoint_extractor/`.
- **Frame Extraction**: Export frame sequences with configurable FPS, resolution (width/height), and before/after temporal buffers.
- **Lossless Movie Cutting**: Extract video segments instantly using FFmpeg's stream copy (`-c copy`) without re-encoding.
- **Re-encode Export**: Encode video segments to apply specific resolution and FPS settings.
- **Remark Support**: Add custom notes to each timepoint for better data organization.
- **Auto-Sorting**: Timepoints are always maintained in chronological order.
- **Unicode Path Support**: Extraction is executed via a generated UTF-8 `.cmd` wrapper to improve compatibility with non-ASCII (e.g., Japanese) paths.

---

## Requirements

1. **VLC Media Player**: Tested on version 3.x.
2. **FFmpeg**: Must be installed and available in your system's **PATH**.

---

## Installation

1. Download `vlc_timepoint_extractor.lua`.
2. Move the file to the VLC extensions directory: `C:\Program Files\VideoLAN\VLC\lua\extensions\`
3. Restart VLC.
4. Open the extension from the menu: `Tools` → `Extensions` → `VLC TimePoint Extractor`

---

## Usage

### 1. Managing Points

| Action | Description |
|--------|-------------|
| **Add TimePoint** | Captures the current playback position and adds it to the list. |
| **Update Remark** | Updates the note on the selected point with the text in the Remark field. |
| **Jump To** | Seeks the video to the selected point. Its remark is automatically populated in the input field. |
| **Remove** | Deletes the selected point. Remaining points are automatically re-labeled to maintain the sequence. |

### 2. Extraction

#### Extract Frames
- Creates a folder named `{video_name}_extracted_frames`.
- A sub-folder is created per point (e.g., `Point0001`).
- Exports images as `.png` based on your FPS and resolution settings.

#### Extract Movie (Lossless)
- Creates a folder named `{video_name}_extracted_movies`.
- Clips the segment defined by "Before" and "After" seconds using lossless stream copying.
- Filename format: `PointXXXX_Remark.ext`

#### Extract Movie (Encode)
- Creates a folder named `{video_name}_extracted_movies`.
- Re-encodes the segment with your resolution and FPS settings applied.
- Filename format: `PointXXXX_Remark_encoded.ext`

---

## Log Files

Each extraction writes the following files to the `timepoint_extractor/` folder inside VLC's user data directory.

| File | Contents |
|------|----------|
| `ffmpeg_last_command.txt` | The last FFmpeg command run (useful for copy/paste testing) |
| `ffmpeg_run.cmd` | The generated wrapper script (UTF-8 BOM + `chcp 65001`) |
| `ffmpeg_last.log` | FFmpeg stdout/stderr output |

> **Note**: These files use fixed names and are overwritten on every extraction.

---

## License

MIT License
