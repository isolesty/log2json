import re
import sys

import requests


def get_arch(repo, codename, col):
    url = "%s/dists/%s/Release" % (repo, codename)
    r = requests.get(url)
    a = re.compile("%s: (.+)" % col)
    if r.ok:
        arch_str = a.findall(r.text)[0]
        return True, arch_str
    else:
        return False, ""

if __name__ == "__main__":
    repo = sys.argv[1]
    codename = sys.argv[2]
    col = sys.argv[3]
    ret, result = get_arch(repo, codename, col)

    print(result)

