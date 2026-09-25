#!/usr/bin/env python3
import sys
import importlib

MODULES_TO_TEST = [
    "torch",
    "torchvision",
    "cv2",
    "PIL",
    "numpy",
]

def run_smoke_tests():
    print("Running verification smoke tests on stripped layer modules...")
    failed = []
    
    for mod in MODULES_TO_TEST:
        try:
            m = importlib.import_module(mod)
            version = getattr(m, "__version__", "unknown")
            print(f"  [PASS] Successfully imported {mod} (v{version})")
        except Exception as e:
            print(f"  [FAIL] Could not import {mod}: {e}")
            failed.append(mod)
            
    if failed:
        print(f"Smoke test failed for: {', '.join(failed)}")
        sys.exit(1)
        
    # Quick tensor compute test
    try:
        import torch
        x = torch.rand(5, 3)
        y = torch.ones(5, 3)
        z = x + y
        print(f"  [PASS] PyTorch tensor arithmetic smoke test succeeded (shape: {z.shape})")
    except Exception as e:
        print(f"  [FAIL] PyTorch computation check failed: {e}")
        sys.exit(1)
        
    print("All smoke tests passed cleanly without missing symbols!")

if __name__ == "__main__":
    run_smoke_tests()
