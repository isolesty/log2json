#!/usr/bin/env python3

import sys
import json
import os
import subprocess

from urllib.request import urlopen

import hashlib

from datetime import datetime


DEBUG = 0

SCRIPTPATH = "/mnt/mirror-snapshot/utils"


def log_print(output):
    if DEBUG:
        print(output)


def gen_md5(str):
    md5str = hashlib.md5(str.encode(encoding='utf-8'))
    return md5str.hexdigest()


def get_deb_details(filepath):
    """Show the control details of deb file.
    depends on dpkg-deb
    filepath: str
    return: str
    TODO: read one deb file only once
    """
    return os.popen('dpkg-deb -f %s' % filepath).read()


def get_filestats(filepath):
    # already chdir to the download path
    filename = os.path.basename(filepath)

    filesize = os.path.getsize(filename)
    try:
        filemd5 = subprocess.check_output(
            "md5sum " + filename + " | awk '{print $1}'", shell=True)
    except subprocess.CalledProcessError as e:
        raise e

    return filesize, filemd5.strip().decode('utf-8')


def gen_changesfile(OneSource):
    changesfile = '''
Source: {0}
Binary: {1}
Architecture: {2}
Version: {3}
Distribution: {4}
Files:
{5}
'''.format(OneSource.source,
           OneSource.binary,
           OneSource.arch,
           OneSource.version,
           OneSource.distribution,
           OneSource.files)

    with open(OneSource.source + ".changes", 'w') as f:
        f.write(changesfile)


class OneSource(object):
    """Pacakges of Source"""

    def __init__(self, source, version, distribution):
        super(OneSource, self).__init__()
        self.source = source
        self.binary = ''
        self.arch = ''
        self.version = version
        self.distribution = distribution
        self.files = []
        self.section = ''
        self.priority = ''

    def _set_binary(self, binary):
        self.binary = self.binary + ' ' + binary

    def _set_details(self, section, priority):
        self.section = section
        self.priority = priority

    def _set_arch(self, arch):
        if arch in self.arch:
            pass
        else:
            self.arch = self.arch + " " + arch

    def _set_files(self, filename, filemd5, filesize):
        if self.section and self.priority:
            # in .changes file, each line start with a blank in "Files:" field
            filestat = " " + filemd5 + " " + filesize + " " + \
                self.section + " " + self.priority + " " + filename
            self.files.append(filestat)
        else:
            raise("Must set section and priority first.")


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
            sys.exit(1)

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
        os.system("cp -r " + SCRIPTPATH + "/rpabase " + rpapath)
        # os.system("cp -r /tmp/rpabase " + rpapath)
        os.chdir(rpapath)
        # includedsc only one .dsc file each time
        dsccmd = 'find ' + TMPDIR + '/src/ -name "*.dsc" -exec reprepro -b ' + \
            rpapath + ' includedsc unstable {} \; >/dev/null 2>&1'
        os.system(dsccmd)
        # includedeb debs in its right component
        for fileitem in jsondetails:
            if fileitem['arch'] == 'source':
                pass
            else:
                for x in fileitem['filelist']:
                    debname = os.path.basename(x)
                    # component
                    if fileitem['component']:
                        os.system("reprepro -b . -C " + fileitem[
                                  'component'] + " includedeb unstable " + TMPDIR + "/deb/" + debname + " >/dev/null 2>&1")
                    else:
                        os.system("reprepro -b .  includedeb unstable " +
                                  TMPDIR + "/deb/" + debname + " >/dev/null 2>&1")

        # os.system("reprepro -b . includedeb unstable " +
        #         TMPDIR + "/deb/*.deb >/dev/null 2>&1")

        # to rpa
        basedir = "/srv/pool/base/rpa/" + rpaname
        wwwdir = "/srv/pool/www/rpa/" + rpaname
        # basedir = "/tmp/base/rpa/" + rpaname
        # wwwdir = "/tmp/www/rpa/" + rpaname

        if len(sys.argv) == 4:
            # update rpa has dirs, remove
            os.system("rm -rf " + basedir)
            os.system("rm -rf " + wwwdir)

        os.mkdir(basedir)
        os.mkdir(wwwdir)

        os.system("cp -rf " + rpapath + "/db " + basedir + "/")
        os.system("cp -rf " + rpapath + "/conf " + basedir + "/")

        os.system("cp -rf " + rpapath + "/dists " + wwwdir + "/")
        os.system("cp -rf " + rpapath + "/pool " + wwwdir + "/")
        os.system("cp -rf " + rpapath + "/checkupdate " + wwwdir + "/")

        # get the rpa size
        sizecmd = "du -sh " + rpapath + "/pool 2>/dev/null | awk '{print $1;}'"
        rpasize = os.popen(sizecmd).read().strip()
        if rpasize:
            data['size'] = rpasize

        # output the result json
        with open(wwwdir + '/checkupdate/result.json', 'w') as f:
            json.dump(data, f)

        # clean
        os.system("rm -rf " + TMPDIR)
        os.system("rm -rf " + rpapath)

        # end, print the rpaname
        print(rpaname)
