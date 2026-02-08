import os
import sys
from pathlib import Path

# --- BUNDLE LOGIC ---
# This ensures that 'import mutagen' works even if the user hasn't installed it.
# It looks for a folder named 'vendor' in the same directory as this script.
script_dir = os.path.dirname(os.path.realpath(__file__))
vendor_dir = os.path.join(script_dir, "vendor")
sys.path.insert(0, vendor_dir)

try:
    from mutagen import File
    from mutagen.mp3 import MP3
    from mutagen.flac import FLAC, Picture
    from mutagen.mp4 import MP4, MP4Cover
    from mutagen.id3 import ID3, APIC
except ImportError:
    print("❌ Error: Mutagen library not found in the 'vendor' folder.")
    print(f"Debug: Searched in {vendor_dir}")
    sys.exit(1)

def inject_artwork(audio_path, image_path):
    """Injects the image data into the audio file's metadata based on format."""
    try:
        audio = File(audio_path)
        with open(image_path, 'rb') as img_file:
            img_data = img_file.read()

        if isinstance(audio, MP3):
            if audio.tags is None:
                audio.add_tags()
            audio.tags.add(APIC(
                encoding=3,  # UTF-8
                mime='image/jpeg',
                type=3,  # Front Cover
                desc=u'Cover',
                data=img_data
            ))
            audio.save()

        elif isinstance(audio, FLAC):
            picture = Picture()
            picture.data = img_data
            picture.type = 3
            picture.mime = 'image/jpeg'
            audio.add_picture(picture)
            audio.save()

        elif isinstance(audio, MP4):
            # FORMAT_JPEG is standard for 'covr' atoms
            audio.tags['covr'] = [MP4Cover(img_data, imageformat=MP4Cover.FORMAT_JPEG)]
            audio.save()
            
        return True
    except Exception as e:
        print(f"   ❌ Error injecting into {audio_path.name}: {str(e)}")
        return False

def process_folder(folder_path):
    """Checks a single folder for missing art and performs injection."""
    path = Path(folder_path)
    valid_names = ['folder.jpg', 'cover.jpg', 'album.jpg', 'folder.png', 'cover.png']
    
    # 1. Find the source image in the folder
    source_art = None
    for name in valid_names:
        if (path / name).exists():
            source_art = path / name
            break
    
    if not source_art:
        return 0

    # 2. Identify audio files
    audio_files = list(path.glob('*.mp3')) + list(path.glob('*.flac')) + list(path.glob('*.m4a'))
    fixed_in_folder = 0

    for audio_path in audio_files:
        try:
            audio = File(audio_path)
            has_art = False

            # Check if embedded art already exists
            if isinstance(audio, MP3) and audio.tags:
                if any(k.startswith("APIC") or k.startswith("PIC") for k in audio.tags.keys()):
                    has_art = True
            elif isinstance(audio, FLAC) and audio.pictures:
                has_art = True
            elif isinstance(audio, MP4) and audio.tags and 'covr' in audio.tags:
                has_art = True

            # 3. Inject if missing
            if not has_art:
                if inject_artwork(audio_path, source_art):
                    fixed_in_folder += 1
        except Exception:
            continue
            
    if fixed_in_folder > 0:
        print(f"✅ FIXED: '{path.name}' ({fixed_in_folder} tracks updated)")
    
    return fixed_in_folder

# --- Execution ---
if __name__ == "__main__":
    # If Swift passes a path argument, use it; otherwise, default to a placeholder
    if len(sys.argv) > 1:
        root_music_dir = sys.argv[1]
    else:
        print("⚠️ No path provided to Python script. Usage: python3 inject_art.py <path>")
        sys.exit(1)

    print(f"--- Starting Art Injection in: {root_music_dir} ---")
    total_fixed = 0

    # Walk through all subdirectories
    for root, dirs, files in os.walk(root_music_dir):
        total_fixed += process_folder(root)

    print(f"\nTask Complete. Total tracks fixed: {total_fixed}")