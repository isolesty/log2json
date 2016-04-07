#!/usr/bin/env python3

import sys

# xml parser
import json

if __name__ == '__main__':
    if len(sys.argv) == 3:
        basejson = sys.argv[1]
        key = sys.argv[2]

        with open(basejson, 'r') as f:
            basedata = json.load(f)

        print(basedata[key])
