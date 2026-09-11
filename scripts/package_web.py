"""Package only generated application assets, excluding local smoke tests."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parent.parent
source = root / "gui" / "build" / "web"
destination = root / "dist" / "brainstory-web.zip"
destination.parent.mkdir(exist_ok=True)
with ZipFile(destination, "w", ZIP_DEFLATED) as archive:
    for path in sorted(source.rglob("*")):
        if path.is_file() and path.name != "web_engine_smoke.html":
            archive.write(path, path.relative_to(source))
print(destination)
