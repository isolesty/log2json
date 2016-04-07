#!/usr/bin/env python3

import sys
import json
import os

from urllib.request import urlopen

import hashlib

from datetime import datetime


DEBUG = 0


def log_print(output):
    if DEBUG:
        print(output)


def gen_md5(str):
    md5str = hashlib.md5(str.encode(encoding='utf-8'))
    return md5str.hexdigest()

if __name__ == '__main__':
    # usage:
    # newpra.py xxx.json ppa-baseurl [rpaname]
    # newrpa.py result.json http://pools.corp.deepin.com/ppa/debian0311/
    # [e21b073b0d7d63d4b53c65b235309f37]

    if len(sys.argv) > 1:
        # get file list to download
        resultjson = sys.argv[1]
        baseurl = sys.argv[2]

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

        # sometimes not any packages updated
        if not jsondetails:
            print("There is no packages updated in this checkupdate, exit.")
            os._exit(1)

        # download all files
        if len(sys.argv) == 4:
            rpaname = sys.argv[3]
        else:
            rpaname = gen_md5(
                baseurl + datetime.now().strftime("%Y-%m-%d~%H%M%S"))

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

        # make a new rpa from template
        os.system("cp -r /mnt/mirror-snapshot/utils/rpabase " + rpapath)
        # os.system("cp -r /tmp/rpabase " + rpapath)
        os.chdir(rpapath)
        # includedsc only one .dsc file each time
        dsccmd = 'find ' + TMPDIR + '/src/ -name "*.dsc" -exec reprepro -b ' + \
            rpapath + ' includedsc unstable {} \; >/dev/null 2>&1'
        os.system(dsccmd)
        os.system("reprepro -b . includedeb unstable " +
                  TMPDIR + "/deb/*.deb >/dev/null 2>&1")

        # to rpa
        basedir = "/srv/pool/base/rpa/" + rpaname
        wwwdir = "/srv/pool/www/rpa/" + rpaname
        # basedir = "/tmp/base/rpa/" + rpaname
        # wwwdir = "/tmp/www/rpa/" + rpaname

        if len(sys.argv) == 4:
            # update rpa has dirs
            pass
        else:
            os.mkdir(basedir)
            os.mkdir(wwwdir)

        os.system("cp -rf " + rpapath + "/db " + basedir + "/")
        os.system("cp -rf " + rpapath + "/conf " + basedir + "/")

        os.system("cp -rf " + rpapath + "/dists " + wwwdir + "/")
        os.system("cp -rf " + rpapath + "/pool " + wwwdir + "/")
        os.system("cp -rf " + rpapath + "/checkupdate " + wwwdir + "/")

        # output the result json
        with open(wwwdir + '/checkupdate/result.json', 'w') as f:
            json.dump(data, f)

        # clean
        os.system("rm -rf " + TMPDIR)
        os.system("rm -rf " + rpapath)

        # end, print the rpaname
        print(rpaname)
