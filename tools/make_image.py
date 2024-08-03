import numpy as np
from PIL import Image
import argparse

def get_args():
    parser = argparse.ArgumentParser(description='Convert pixel data to image')

    parser.add_argument('input', type=str)
    parser.add_argument('--output', '-o', type=str, default='output.png')

    return parser.parse_args()

def main(args):
    # Load the pixel data
    with open(args.input, "r") as file:
        lines = file.readlines()

    pixels = []
    for line in lines:
        objs = line.split()
        if objs[0] == '//':
            continue
        pixels.extend([int(line.strip(), 16) for line in objs])

    # Convert pixel data to an image
    width, height = 256, 240
    image = np.zeros((height, width, 3), dtype=np.uint8)

    for y in range(height):
        for x in range(width):
            color = pixels[y * width + x]
            # Example: convert 6-bit color to RGB
            r = (color >> 4) & 0x3
            g = (color >> 2) & 0x3
            b = color & 0x3
            image[y, x] = [r * 85, g * 85, b * 85]  # Scale to 8-bit per channel

    # Save the image
    img = Image.fromarray(image, 'RGB')
    img.save(args.output)

if __name__ == '__main__':
    args = get_args()
    main(args)