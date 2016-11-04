#!/usr/bin/env python3

import sys
import json
import os
import subprocess
import re

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
    return: str str str
    TODO: read one deb file only once
    """
    controlfile = os.popen('dpkg-deb -f %s' % filepath).readlines()
    for line in controlfile:
        line = line.strip()
        if line.startswith("Package: "):
            debname = line[9:]
        if line.startswith("Section: "):
            section = line[9:]
        if line.startswith("Priority: "):
            priority = line[10:]

    return debname, section, priority


def get_filestats(filename):
    # already chdir to the download path
    filesize = os.path.getsize(filename)
    try:
        filemd5 = subprocess.check_output(
            "md5sum " + filename + " | awk '{print $1}'", shell=True)
    except subprocess.CalledProcessError as e:
        raise e

    return filesize, filemd5.strip().decode('utf-8')


def gen_changesfile(Source):
    # OneSource.files is a list
    files = ''
    # section and priority may be wrong
    for filestat in Source.files:
        files = files + \
            filestat.replace('section', Source.section).replace(
                'priority', Source.priority) + "\n"

    changescontent = '''Source: {0}
Binary: {1}
Architecture: {2}
Version: {3}
Distribution: {4}
Files:
{5}
'''.format(Source.source,
           Source.binary,
           Source.arch,
           Source.version,
           Source.distribution,
           files)

    return Source.source, changescontent


def search_source(OneSourcelist, name):
    for onesource in OneSourcelist:
        if name == onesource.source:
            return onesource

    return 0


def gen_source(itemlist):
    sourcelist = []
    # from jsondetails to OneSource list
    sourcere = re.compile(".*/\w+/(.*)/.*")
    for item in itemlist:
        source = sourcere.findall(item['filelist'][0])[0]
        thissource = search_source(sourcelist, source)
        # a known source
        if thissource:
            thissource._set_arch(item['arch'])

            if item['arch'] == 'source':
                pass
            else:
                # one deb file is enough
                debname, section, priority = get_deb_details(
                    os.path.basename(item['filelist'][0]))

                thissource._set_binary(debname)
                # section is default value
                if thissource.section == 'section':
                    thissource._set_details(section, priority)

            for filepath in item['filelist']:
                filename = os.path.basename(filepath)
                filesize, filemd5 = get_filestats(filename)
                thissource._set_files(filename, filesize, filemd5)

        else:
            newsource = OneSource(source)
            newsource._set_arch(item['arch'])
            newsource._set_version(item['newversion'])

            if item['arch'] == 'source':
                pass
            else:
                # one deb file is enough
                debname, section, priority = get_deb_details(
                    os.path.basename(item['filelist'][0]))

                newsource._set_binary(debname)
                newsource._set_details(section, priority)

            for filepath in item['filelist']:
                filename = os.path.basename(filepath)
                filesize, filemd5 = get_filestats(filename)
                newsource._set_files(filename, filesize, filemd5)

            sourcelist.append(newsource)

    return sourcelist


class OneSource(object):
    """Pacakges of Source"""

    def __init__(self, source):
        super(OneSource, self).__init__()
        self.source = source
        self.binary = ''
        self.arch = ''
        self.version = ''
        self.distribution = 'unstable'
        self.files = []
        self.section = 'section'
        self.priority = 'priority'

    def _set_version(self, version):
        self.version = version

    def _set_dist(self, distribution):
        self.distribution = distribution

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

    def _set_files(self, filename, filesize, filemd5):
        # in .changes file, each line start with a blank in "Files:" field
        filestat = " " + filemd5 + " " + str(filesize) + " " + \
            self.section + " " + self.priority + " " + filename
        self.files.append(filestat)


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
        # os.mkdir("src")
        # os.mkdir("deb")

        # download all files
        for fileitem in jsondetails:
            for x in fileitem['filelist']:
                fileurl = baseurl + "/" + x
                log_print(fileurl)
                g = urlopen(fileurl)
                with open(os.path.basename(x), 'b+w') as f:
                    f.write(g.read())
        # generate .changes files
        sourcelist = gen_source(jsondetails)
        for item in sourcelist:
            name, content = gen_changesfile(item)
            with open(name + ".changes", 'w') as f:
                f.write(content)

            # make a new rpa from template
        os.system("cp -r " + SCRIPTPATH + "/rpabase " + rpapath)
        # os.system("cp -r /tmp/rpabase " + rpapath)
        os.chdir(rpapath)
        # include *.changes
        changescmd = 'find ' + TMPDIR + '/ -name "*.changes" -exec' + \
            ' reprepro -b ' + rpapath + \
            ' --ignore=missingfield include unstable {} \; >/dev/null 2>&1'
        try:
            subprocess.check_output(changescmd, shell=True)
        except subprocess.CalledProcessError as e:
            print(e.output)

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
