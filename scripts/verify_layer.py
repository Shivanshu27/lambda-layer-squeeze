#!/usr/bin/env python3
import sys
import os
from pathlib import Path

AWS_LAMBDA_MAX_BYTES = 250 * 1024 * 1024  # 250 MB uncompressed limit

def get_directory_size(path: Path) -> int:
    total = 0
    for entry in path.rglob('*'):
        if entry.is_file() and not entry.is_symlink():
            total += entry.stat().st_size
    return total

def format_bytes(size: int) -> str:
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024.0:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{size:.2f} TB"

def main():
    target_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/python")
    
    if not target_dir.exists():
        print(f"Error: Target path '{target_dir}' does not exist.")
        sys.exit(1)
        
    print(f"Analyzing layer footprint at: {target_dir}")
    total_bytes = get_directory_size(target_dir)
    total_formatted = format_bytes(total_bytes)
    max_formatted = format_bytes(AWS_LAMBDA_MAX_BYTES)
    
    # Calculate top 10 largest packages
    package_sizes = {}
    for item in target_dir.iterdir():
        if item.is_dir():
            package_sizes[item.name] = get_directory_size(item)
        elif item.is_file():
            package_sizes[item.name] = item.stat().st_size
            
    sorted_packages = sorted(package_sizes.items(), key=lambda x: x[1], reverse=True)
    
    print("-" * 60)
    print(f"{'Package / Item':<35} | {'Size':<15}")
    print("-" * 60)
    for name, size in sorted_packages[:10]:
        print(f"{name:<35} | {format_bytes(size):<15}")
    print("-" * 60)
    print(f"Total Layer Size: {total_formatted} / {max_formatted}")
    
    percentage = (total_bytes / AWS_LAMBDA_MAX_BYTES) * 100
    print(f"AWS Lambda Quota Utilization: {percentage:.1f}%")
    
    if total_bytes > AWS_LAMBDA_MAX_BYTES:
        excess = format_bytes(total_bytes - AWS_LAMBDA_MAX_BYTES)
        print(f"FAIL: Layer exceeds AWS Lambda 250MB limit by {excess}!")
        sys.exit(1)
    else:
        headroom = format_bytes(AWS_LAMBDA_MAX_BYTES - total_bytes)
        print(f"SUCCESS: Layer is within AWS limits with {headroom} headroom remaining.")
        sys.exit(0)

if __name__ == "__main__":
    main()
