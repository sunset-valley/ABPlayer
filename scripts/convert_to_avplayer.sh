#!/bin/bash

# ==============================================================================
# AVPlayer Video Converter Script
# Converts video files to H.264/AAC MP4 format for maximum compatibility.
# ==============================================================================

if ! command -v ffmpeg &>/dev/null; then
	echo "❌ Error: ffmpeg is not installed. Please install it first (e.g., 'brew install ffmpeg')."
	exit 1
fi

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <source_directory>"
	echo "Example: $0 ./my_videos"
	exit 1
fi

SOURCE_DIR="$1"
OUTPUT_DIR="${SOURCE_DIR}/output"

if [ ! -d "$SOURCE_DIR" ]; then
	echo "❌ Error: Source directory '$SOURCE_DIR' does not exist."
	exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "🚀 Starting conversion..."
echo "📂 Source: $SOURCE_DIR"
echo "📂 Output: $OUTPUT_DIR"
echo "--------------------------------------------------"

# Process files
find "$SOURCE_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.webm" -o -iname "*.m4v" \) -print0 | while IFS= read -r -d '' file; do
	filename=$(basename -- "$file")
	filename_no_ext="${filename%.*}"
	output_file="$OUTPUT_DIR/${filename_no_ext}.mp4"

	echo "🎬 Processing: $filename"

	ffmpeg -nostdin -i "file:$file" \
		-c:v libx264 -profile:v high -level:v 4.1 -pix_fmt yuv420p \
		-preset medium -crf 23 \
		-c:a aac -b:a 128k \
		-movflags +faststart \
		-hide_banner -loglevel error -stats \
		-y "$output_file"

	if [ $? -eq 0 ]; then
		echo "✅ Successfully converted to: $output_file"
	else
		echo "❌ Failed to convert: $filename"
	fi
	echo "--------------------------------------------------"
done

echo "🎉 All done! Converted files are in: $OUTPUT_DIR"
