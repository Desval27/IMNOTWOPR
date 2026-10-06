#!/bin/sh

find . -regex '.*\.\(cpp\|h\)' -exec clang-format -style=file -i {} +
echo "Done, maybe."
