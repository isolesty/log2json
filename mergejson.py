#!/usr/bin/env python3

import sys

# xml parser
import json

if __name__ == '__main__':
    if len(sys.argv) > 2:
        basejson = sys.argv[1]
        updatejson = sys.argv[2]

        with open(basejson, 'r') as f:
            basedata = json.load(f)

        with open(updatejson, 'r') as f:
            updatedata = json.load(f)

        basedata['details'] += updatedata['details']

        with open(basejson, 'w') as f:
            json.dump(basedata, f)
