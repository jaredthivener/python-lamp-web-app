"""Load every shared object under /usr/local, as the image's own Python: exit 1 if one cannot be.

The image has no shell and only the system libraries the Dockerfile copies into it, so a wheel that
needs another one would otherwise fail when the app first imports it. Run as:
    docker run --rm -i IMAGE python - < .github/scripts/check-image-libs.py
"""

import ctypes
import pathlib
import sys

failed = []
count = 0
for path in sorted(pathlib.Path("/usr/local").rglob("*.so*")):
    if not path.is_file():
        continue
    count += 1
    try:
        ctypes.CDLL(str(path))
    except OSError as error:
        failed.append(f"{path}: {error}")

print(f"{count} shared objects, {len(failed)} failed to load")
print("\n".join(failed))
sys.exit(bool(failed))
