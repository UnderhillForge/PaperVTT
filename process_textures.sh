#!/bin/bash
BASE_DEST="assets/world/textures/world"
SRC_DIR="/home/js/Downloads/textures"
TEMP_DIR="/tmp/texture_extract"

mkdir -p "$BASE_DEST"

declare -A MAPPINGS=(
    ["Bark"]="trees_bark"
    ["Grass"]="ground_grass"
    ["Ground"]="ground_dirt"
    ["Gravel"]="ground_dirt"
    ["Rock"]="rock_stone"
    ["Rocks"]="rock_stone"
    ["Marble"]="surface_stone"
    ["Bricks"]="surface_stone"
    ["PavingStones"]="surface_stone"
    ["Tiles"]="surface_stone"
    ["Metal"]="surface_metal"
    ["Wood"]="surface_wood"
    ["WoodFloor"]="surface_wood"
    ["Planks"]="surface_wood"
    ["RoofingTiles"]="surface_roof"
    ["Snow"]="environment_snow_ice"
    ["Ice"]="environment_snow_ice"
    ["Lava"]="environment_lava"
)

imported_count=0
skipped_zips=()

for zip_path in "$SRC_DIR"/*.zip; do
    zip_file=$(basename "$zip_path")
    zip_stem="${zip_file%.*}"
    
    category=""
    for key in "${!MAPPINGS[@]}"; do
        if [[ "$zip_file" == "$key"* ]]; then
            category="${MAPPINGS[$key]}"
            break
        fi
    done

    if [[ -z "$category" ]]; then
        skipped_zips+=("$zip_file")
        continue
    fi

    dest_dir="$BASE_DEST/$category/$zip_stem"
    mkdir -p "$dest_dir"

    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    unzip -q "$zip_path" -d "$TEMP_DIR"

    found_images=0
    # Copy only images, preserve filenames
    find "$TEMP_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) | while read -r img; do
        cp "$img" "$dest_dir/"
    done
    
    if [ "$(ls -A "$dest_dir")" ]; then
        imported_count=$((imported_count + 1))
    else
        rmdir "$dest_dir"
        skipped_zips+=("$zip_file (no images)")
    fi
done

echo "TOTAL_IMPORTED=$imported_count"
echo "SKIPPED_ZIPS=${skipped_zips[*]}"
