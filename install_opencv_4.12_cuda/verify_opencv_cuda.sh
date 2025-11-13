python3 - << 'PY'
import cv2, sys
print("OpenCV:", cv2.__version__)
print("CUDA in build info? ", "CUDA" in cv2.getBuildInformation())
print("GStreamer in build info? ", "GStreamer" in cv2.getBuildInformation())
try:
    import cv2.dnn as dnn
    print("DNN module present:", hasattr(dnn, "readNet"))
    # This will raise if CUDA/TRT backends are not compiled:
    print("Backends check OK")
except Exception as e:
    print("DNN check error:", e, file=sys.stderr)
PY
