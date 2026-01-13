# VLC TimePoint Extractor

A VLC media player extension designed to manage video timepoints and automate frame sequence or clip extraction using FFmpeg.

This tool is particularly useful for technical engineers, researchers, and developers working on **computer vision datasets**, **visual inspection analysis**, or **video editing workflows**.

## Features

- **TimePoint Management**: Save specific timestamps with a structured naming convention (`Point0001`, `Point0002`, etc.).
- **Metadata Storage**: Automatically saves/loads data to a `.tp` file in the same directory as the video file.
- **Frame Extraction**: Export frame sequences with configurable FPS, resolution (width/height), and "before/after" temporal buffers.
- **Lossless Movie Cutting**: Instantly extract video segments using FFmpeg's stream copy (`-c copy`) without re-encoding.
- **Remark Support**: Add custom notes/remarks to each timepoint for better data organization.
- **Auto-Sorting**: Timepoints are always maintained in chronological order.

## Requirements

1. **VLC Media Player**: Tested on version 3.x.
2. **FFmpeg**: Must be installed and added to your system's **PATH** environment variable.

## Installation

1. Download the `timepoint_extractor.lua` script.
2. Move the script to the VLC extensions directory:
   - **Windows**: `C:\Program Files\VideoLAN\VLC\lua\extensions`
3. Restart VLC.
4. Open the extension from the menu: `View` -> `VLC TimePoint Extractor`.

## Usage

### 1. Managing Points
- **Add TimePoint**: Captures the current video time and adds it to the list.
- **Update Remark**: Enter text in the Remark field and click this to update an existing point.
- **Jump To**: Select a point in the list to seek the video to that specific time.
- **Remove**: Deletes the selected point and automatically re-labels remaining points.

### 2. Extraction
- **Extract Frames**: 
  - Creates a folder named `{video_name}_frames`.
  - Exports images as `.png` based on your FPS and resolution settings.
- **Extract Movie**: 
  - Creates a folder named `{video_name}_cuts`.
  - Clips the video segment based on "Before" and "After" seconds.
  - Filename format: `PointXXXX_Remark.ext`.

## Use Case: AI Dataset Preparation
For engineers developing automated visual inspection systems (e.g., using YOLOX or OpenCV), this tool simplifies the process of labeling and extracting high-quality training samples directly from raw video footage.


