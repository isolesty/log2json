import os
import sys

# for random TMPDIR
import random
import string

import subprocess


# class Source and related functions


class Source(object):
    """docstring for Source"""

    def __init__(self, name):
        super(Source, self).__init__()
        self.name = name
        # source version
        self.version = ''
        self.oldversion = '0'

        # source's all debs
        self.deblist = []

        # source's binary is all debs' name for quick search
        self.binary = ''
        # self.arch is all debs' arch
        self.arch = ''

        self.section = 'section'
        self.priority = 'priority'

        self.distribution = 'unstable'

        # source's changelog diff
        self.changelogdiff = ''
        # source's smallest deb name to extract
        self.minsize = 0
        self.mindeb = ''
        # source's commit logs
        self.commitlog = ''


# class deb and related functions


def gen_randomstr(length):
    """Create a random string
    length: int
    return str
    """
    randomstr = string.ascii_letters + string.digits
    return ''.join([random.choice(randomstr) for i in range(length)])


def get_deb_details(filepath):
    """Show the control details of deb file.
    depends on dpkg-deb
    filepath: str
    return: deb
    TODO: read one deb file only once
    """
    controlfile = os.popen('dpkg-deb -f %s' % filepath).readlines()
    for line in controlfile:
        line = line.strip()
        if line.startswith("Package: "):
            debname = line[9:]
        if line.startswith("Installed-Size: "):
            size = int(line[15:])
        if line.startswith("Section: "):
            section = line[9:]
        if line.startswith("Priority: "):
            priority = line[10:]

    return debname, size, section, priority


def get_changelog_file(filepath):
    """Get a deb's changelog path in deb.
    depends on dpkg-deb, grep, awk.
    filepath: str
    return 1 if deb has changelogs and set pacakge's changelogpath else 0.
    """
    # some deb files contain multi changelog files, only one is useful
    # example:
    # -rw-r--r-- root/root     38974 2016-01-13 23:09 ./usr/share/doc/python3.5/changelog.Debian.gz
    # lrwxrwxrwx root/root         0 2016-01-14 02:55 ./usr/share/doc/python3.5/changelog.gz -> NEWS.gz
    # and another
    # -rw-r--r-- root/root     23459 2015-12-10 12:32 ./usr/share/doc/vim-common/changelog.gz
    # -rw-r--r-- root/root     84110 2016-01-25 10:25 ./usr/share/doc/vim-common/changelog.Debian.gz
    # filepath="./usr/share/doc/vim-common/changelog.gz\n./usr/share/doc/vim-common/changelog.Debian.gz"

    # changelog*.gz always in usr/share/doc/
    cmd = "dpkg-deb -c " + filepath + \
        " | grep changelog | grep 'usr/share/doc' | awk '$3!=0{print $6;}'"
    # strip the \n in filepath
    filepath = os.popen(cmd).read().strip().split('\n')
    changelogpath = ''

    if filepath:
        # multi changelog files in filepath
        if len(filepath) > 1:
            for x in filepath:
                if os.path.split(x)[1] == 'changelog.Debian.gz':
                    changelogpath = x
                    break
            # changelog.Debian.gz is not in deb file list
            if not changelogpath:
                for x in filepath:
                    # a file has changelog and Debian may be the right one?
                    if x.find('Debian') != -1:
                        filepath = x
        else:
            changelogpath = filepath[0]
        return changelogpath
    else:
        # deb file doesn't contain a changelog,
        return ''


def get_changelog(debpath, changelogpath, baseversion, updateversion):
    """Get changelogs of package.
    depends on dpkg-deb, zcat, sed.
    debpath: str
    changelogpath: str
    baseversion: str
    updateversion: str
    return changelogs: str
    """
    # create tmp dir
    randomstr = gen_randomstr(10)
    TMPDIR = '/tmp/diffchangelog-' + randomstr

    extractcmd = "dpkg-deb -x " + debpath + " " + TMPDIR

    extractdeb = os.system(extractcmd)
    # extract deb failed?
    if extractdeb != 0:
        print("extract deb file failed.")
        return 9

    zcatcmd = "cd " + TMPDIR + " && zcat " + changelogpath

    changelogs = os.popen(zcatcmd).read()

    # clean TMPDIR
    cleancmd = "rm -rf " + TMPDIR
    os.system(cleancmd)

    return changelogs


def get_filestats(filename):
    # already chdir to the download path
    filesize = os.path.getsize(filename)
    try:
        filemd5 = subprocess.check_output(
            "md5sum " + filename + " | awk '{print $1}'", shell=True)
    except subprocess.CalledProcessError as e:
        raise e

    return filesize, filemd5.strip().decode('utf-8')


class Deb(object):
    """docstring for Deb"""

    def __init__(self, name):
        super(Deb, self).__init__()
        self.name = name

        # informations from dpkg-deb -f
        self.arch = ''
        self.size = 0
        self.section = ''
        self.priority = ''

        # changelogs information from dpkg-deb -c
        self.changelogpath = ''

        # file's stats
        self.filesize = 0
        self.md5 = ''

    def _set_details(self, debname, size, section, priority):
        self.name = debname
        self.size = size
        self.section = section
        self.priority = priority

    def _set_changelogpath(self, changelogpath):
        self.changelogpath = changelogpath

    def _set_stats(self, size, md5):
        self.filesize = size
        self.md5sum = md5
