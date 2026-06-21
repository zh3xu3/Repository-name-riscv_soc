#!/usr/bin/env python3
"""Convert objcopy verilog hex output to inst_mem.hex format.
objcopy verilog: bytes in little-endian order per line
inst_mem ($readmemh): big-endian 32-bit words per line
"""
import sys

def convert(input_file, output_file, num_words=1024):
    words = [0] * num_words
    addr = 0

    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('@'):
                addr = int(line[1:], 16)
                continue
            # Parse bytes (little-endian in objcopy verilog output)
            bytes_list = line.split()
            for b in bytes_list:
                word_idx = addr // 4
                byte_offset = addr % 4
                if word_idx < num_words:
                    # Little-endian: byte at addr N goes to bits [byte_offset*8 +: 8]
                    words[word_idx] |= (int(b, 16) << (byte_offset * 8))
                addr += 1

    with open(output_file, 'w') as f:
        for w in words:
            f.write(f"{w:08x}\n")

    print(f"Converted {input_file} -> {output_file} ({num_words} words)")

if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1024)
