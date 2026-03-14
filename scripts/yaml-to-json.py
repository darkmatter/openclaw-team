#!/usr/bin/env python3
"""Convert a simple YAML file (key: value, with | multiline) to JSON."""
import json
import sys

def yaml_to_json(input_path, output_path):
    data = {}
    current_key = None
    current_val = []

    with open(input_path) as f:
        for line in f:
            stripped = line.rstrip('\n')
            if not stripped.startswith(' ') and ':' in stripped:
                if current_key:
                    data[current_key] = '\n'.join(current_val).rstrip('\n') if len(current_val) > 1 else (current_val[0] if current_val else '')
                k_v = stripped.split(':', 1)
                current_key = k_v[0].strip()
                v = k_v[1].strip()
                current_val = [] if v == '|' else [v]
            elif current_key and stripped.startswith('    '):
                current_val.append(stripped[4:])

        if current_key:
            data[current_key] = '\n'.join(current_val).rstrip('\n') if len(current_val) > 1 else (current_val[0] if current_val else '')

    # Ensure private_key has trailing newline
    if 'private_key' in data and not data['private_key'].endswith('\n'):
        data['private_key'] += '\n'

    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)

if __name__ == '__main__':
    yaml_to_json(sys.argv[1], sys.argv[2])
