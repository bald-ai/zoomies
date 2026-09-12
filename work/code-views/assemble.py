from pathlib import Path
source = Path(__file__).resolve().parent / "01-rooms.html"
output = source.parent.parent / "zoomies-code-views.html"
output.write_text(source.read_text())
print(output)
