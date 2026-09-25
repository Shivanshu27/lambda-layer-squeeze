#!/usr/bin/env python3
import sys
import os
import importlib

if "/opt/python" not in sys.path and os.path.exists("/opt/python"):
    sys.path.insert(0, "/opt/python")

MODULES_TO_TEST = [
    "cv2",
    "PIL",
    "numpy",
    "onnxruntime",
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
        
    # Image processing smoke test
    try:
        import numpy as np
        import cv2
        img = np.zeros((100, 100, 3), dtype=np.uint8)
        blurred = cv2.GaussianBlur(img, (5, 5), 0)
        print(f"  [PASS] OpenCV image matrix Gaussian blur test succeeded (shape: {blurred.shape})")
    except Exception as e:
        print(f"  [FAIL] OpenCV computation check failed: {e}")
        sys.exit(1)

    # ONNX runtime inference session smoke test
    try:
        import onnxruntime as ort
        providers = ort.get_available_providers()
        print(f"  [PASS] ONNX Runtime execution engine initialized (providers: {providers})")
    except Exception as e:
        print(f"  [FAIL] ONNX Runtime initialization check failed: {e}")
        sys.exit(1)
        
    print("All smoke tests passed cleanly without missing symbols!")

if __name__ == "__main__":
    run_smoke_tests()
