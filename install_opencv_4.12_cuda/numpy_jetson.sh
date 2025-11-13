# See which interpreter you're using
python3 -c 'import sys; print(sys.executable)'

# Remove any NumPy 2.x first
python3 -m pip uninstall -y numpy

# Install 1.26.4 (Ubuntu may require --break-system-packages)
python3 -m pip install --no-cache-dir "numpy==1.26.4" --break-system-packages

# Verify
python3 - << 'PY'
import numpy as np
print("NumPy:", np.__version__, " @", np.__file__)
PY
