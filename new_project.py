import sys
import os
import shutil
from datetime import datetime

def format_datetime(dt):
    is_windows = sys.platform.startswith("win")

    if is_windows:
        fmt = "%#m/%#d/%Y %#I:%M%p"
    else:
        fmt = "%-m/%-d/%Y %-I:%M%p"

    return dt.strftime(fmt).lower()

name = sys.argv[1]
shutil.rmtree(name)
os.mkdir(name)

shutil.copyfile("./template/main.odin",f"./{name}/main.odin")
markdown = f"""\
# {name}

empty description

## Started at

{format_datetime(datetime.now())}
"""
with open(f"./{name}/README.md", "w") as file:
    file.write(markdown)