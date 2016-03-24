#!/usr/bin/env python3

import re
import sys
import json
import os

from urllib.request import urlopen

import hashlib

from datetime import datetime


DEBUG = 1


def log_print(output):
    if DEBUG:
        print(output)


def gen_md5(str):
    md5str = hashlib.md5(str.encode(encoding='utf-8'))
    return md5str.hexdigest()

if __name__ == '__main__':
    # usage:
    # newrpa.py result.json http://pools.corp.deepin.com/ppa/debian0311/

    if len(sys.argv) > 1:
        # get file list to download
        resultjson = sys.argv[1]
        with open(resultjson, 'r') as f:
            data = json.load(f)

        modifytime = data['time']

        # example:
        # {'repo': 'debian', 'filelist':
        # ['pool/non-free/e/ebook-dev-alp/ebook-dev-alp_200407-2.dsc',
        # 'pool/non-free/e/ebook-dev-alp/ebook-dev-alp_200407.orig.tar.gz',
        # 'pool/non-free/e/ebook-dev-alp/ebook-dev-alp_200407-2.diff.gz'],
        # 'name': 'ebook-dev-alp', 'newversion': '200407-1', 'type': 'update',
        # 'arch': 'source', 'oldversion': '200407-2'}
        jsondetails = data['details']

        # download all files
        baseurl = sys.argv[2]
        rpaname = gen_md5(baseurl + datetime.now().strftime("%Y-%m-%d~%H%M%S"))
        rpapath = "/tmp/" + rpaname
        TMPDIR = "/tmp/rpa-" + rpaname

        log_print(TMPDIR)

        os.mkdir(TMPDIR)
        os.chdir(TMPDIR)
        os.mkdir("src")
        os.mkdir("deb")

        for fileitem in jsondetails:
            if fileitem['arch'] == 'source':
                for x in fileitem['filelist']:
                    fileurl = baseurl + "/" + x
                    log_print(fileurl)
                    g = urlopen(fileurl)
                    with open("src/" + os.path.basename(x), 'b+w') as f:
                        f.write(g.read())
            else:
                for x in fileitem['filelist']:
                    fileurl = baseurl + "/" + x
                    log_print(fileurl)
                    g = urlopen(fileurl)
                    with open("deb/" + os.path.basename(x), 'b+w') as f:
                        f.write(g.read())

        # make a new rpa
        os.system("cp -r /tmp/rpabase " + rpapath)
        os.chdir(rpapath)
        # includedsc only one .dsc file each time
        dsccmd = 'find ' + TMPDIR + '/src/ -name "*.dsc" -exec reprepro -b ' + \
            rpapath + ' includedsc unstable {} \;'
        log_print(dsccmd)
        os.system(dsccmd)
        os.system("reprepro -b . includedeb unstable " + TMPDIR + "/deb/*.deb")
