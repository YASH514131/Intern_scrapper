import os
from PIL import Image

# List of mipmap folders
mipmap_folders = [
    'android/app/src/main/res/mipmap-mdpi',
    'android/app/src/main/res/mipmap-hdpi',
    'android/app/src/main/res/mipmap-xhdpi',
    'android/app/src/main/res/mipmap-xxhdpi',
    'android/app/src/main/res/mipmap-xxxhdpi',
]

for folder in mipmap_folders:
    png_path = os.path.join(folder, 'ic_launcher.png')
    jpg_path = png_path  # Actually a JPEG with .png extension
    if os.path.exists(jpg_path):
        try:
            with Image.open(jpg_path) as im:
                rgb_im = im.convert('RGBA')
                rgb_im.save(png_path, format='PNG')
                print(f'Converted {jpg_path} to PNG')
        except Exception as e:
            print(f'Failed to convert {jpg_path}: {e}')
