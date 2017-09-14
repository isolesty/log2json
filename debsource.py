import os
import re

# for random TMPDIR
import random
import string

import subprocess

###
# common functions
###


def get_filestats(filename):
    filesize = os.path.getsize(filename)
    try:
        filemd5 = subprocess.check_output(
            "md5sum " + filename + " | awk '{print $1}'", shell=True)
    except subprocess.CalledProcessError as e:
        raise e

    return filesize, filemd5.strip().decode('utf-8')


def gen_randomstr(length):
    """Create a random string
    length: int
    return str
    """
    randomstr = string.ascii_letters + string.digits
    return ''.join([random.choice(randomstr) for i in range(length)])


###
# class Source and related functions
###

def get_commitlog(name, oldversion, newversion):
    """Generate commits between old version and newversion
    name: str
    oldversion: str
    newversion: str
    return commitlog: str
    """
    REPODIR = "/home/leaeasy/git-repo/"
    # get all deepin repos
    try:
        allrepos = [f for f in os.listdir(
            REPODIR) if os.path.isdir(os.path.join(REPODIR, f))]
    except:
        # REPODIR not found
        return 9

    # not deepin packages
    if name not in allrepos:
        return 9

    # version example:
    # 3.0.1-1
    # 2:1.18.1-1
    # 10.1.0.5503~a20p2
    versionre = re.compile("(\d:)?([\d.]+).*")
    oldtag = re.findall(versionre, oldversion)[0][1]
    newtag = re.findall(versionre, newversion)[0][1]

    commitcmd = "cd " + REPODIR + name + \
        " && git log --pretty=oneline --abbrev-commit " + \
        oldtag + ".." + newtag + " && cd - >/dev/null"

    commitlog = os.popen(commitcmd).read()

    if commitlog:
        return gen_commit_url(commitlog, name)
    else:
        return 9


def gen_commit_url(data, name):
    urlbase = "https://github.com/linuxdeepin/" + name + "/commit/"
    for x in data.split('\n'):
        commitid = x.split(" ")[0]
        if commitid:
            data = data.replace(commitid, "<a href='%s%s'>%s</a>" %
                                (urlbase, commitid, commitid))

    return data


class Source(object):
    """docstring for Source"""

    def __init__(self, name):
        super(Source, self).__init__()
        self.name = name
        # source version
        self.version = ''
        self.oldversion = '0'

        # source's all debs
        self.debs = {}

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

    def _set_version(self, version, oldversion):
        self.version = version
        self.oldversion = oldversion

    def _set_arch(self, arch):
        if arch in self.arch:
            pass
        else:
            self.arch = self.arch + " " + arch

    def _set_details(self, section, priority):
        self.section = section
        self.priority = priority

    def _set_distro(self, distro):
        '''
        Get soruce distro from debs if distro is set to ''
        '''
        if not distro:
            if not self.mindeb.changelog:
                self.mindeb.get_changelog()

            distrore = re.compile(r'.* (\w+); urgency')
            distro = re.findall(distrore, self.mindeb.changelog)[0]

        self.distribution = distro

    # TODO: diff from versions of changelog
    # may be set distro in this function is a good choice?
    def _set_changelogdiff(self):
        # not changelogs in mindeb
        if not self.mindeb.changelog:
            diff = 'No changlog found.'
        # a new source
        elif self.oldversion == '0':
            diff = self.mindeb.changelog
        else:
            oldstr = self.name + ' (' + self.oldversion + ') '

            # old version not in changelog, maybe step over some versions?
            header_pattern = re.compile(r'.*;.*urgency=.*\n+')
            changelogs = header_pattern.split(self.mindeb.changelog)
            headers = header_pattern.findall(self.mindeb.changelog)

            diff = ''
            # show max 5 changelog items
            for x in range(0, len(headers)):
                if oldstr in headers[x]:
                    break
                elif x > 4:
                    break
                else:
                    diff = diff + headers[x] + changelogs[x + 1]

        self.changelogdiff = diff

    def _set_minsize(self, deb):
        # some debs don't have changelogs
        if deb.changelogpath == '':
            pass
        # the first deb of this source
        elif self.minsize == 0:
            self.minsize = deb.filesize
            self.mindeb = deb
        elif self.minsize > deb.filesize:
            self.minsize = deb.filesize
            self.mindeb = deb

    def _set_commitlog(self):
        commits = get_commitlog(self.name, self.oldversion, self.version)
        if commits == 9:
            commits = "No commit logs found"

        self.commitlog = commits

    # TODO: Many things to do in this
    def add_debs(self, deb):
        self.debs[deb.name] = deb
        self._set_arch(deb.arch)
        self._set_details(deb.section, deb.priority)
        self._set_minsize(deb)


####
# class Deb and related functions
####

class Deb(object):
    """docstring for Deb"""

    def __init__(self, filename):
        super(Deb, self).__init__()
        self.filename = filename

        # informations from dpkg-deb -f
        self.name = ''
        self.arch = ''
        self.version = ''
        # Installed size
        self.installedsize = 0
        self.section = ''
        self.priority = ''

        # file's stats
        self.filesize = 0
        self.md5 = ''

        # changelogs information from dpkg-deb -c
        self.changelogpath = ''

        self.changelog = ''

    def init_deb(self):
        # initial all deb's information
        # only one deb in one Source should get changelogs
        self._set_stats()
        self._set_details()
        self.get_changelog_path()

    def _set_details(self):
        # get information from dpkg-deb -f
        controlfile = os.popen('dpkg-deb -f %s' % self.filename).readlines()
        for line in controlfile:
            line = line.strip()
            if line.startswith("Package: "):
                self.name = line[9:]
            if line.startswith("Version: "):
                self.version = line[9:]
            if line.startswith("Architecture: "):
                self.arch = line[14:]
            if line.startswith("Installed-Size: "):
                self.installedsize = int(line[15:])
            if line.startswith("Section: "):
                self.section = line[9:]
            if line.startswith("Priority: "):
                self.priority = line[10:]

    def _set_stats(self):
        filesize, md5 = get_filestats(self.filename)
        self.filesize = filesize
        self.md5sum = md5

    def get_changelog_path(self):
        """Get a deb's changelog path in deb.
        depends on dpkg-deb, grep, awk

        some deb files contain multi changelog files, only one is useful
        example:
        ./usr/share/doc/python3.5/changelog.Debian.gz
        ./usr/share/doc/python3.5/changelog.gz -> NEWS.gz
        and another
        ./usr/share/doc/vim-common/changelog.gz
        ./usr/share/doc/vim-common/changelog.Debian.gz
        filepath="./usr/share/doc/vim-common/changelog.gz\n./usr/share/doc/vim-common/changelog.Debian.gz"
        """

        # changelog*.gz always in usr/share/doc/
        cmd = "dpkg-deb -c " + self.filename + \
            " | grep -i changelog | grep 'usr/share/doc'" + \
            " | awk '$3!=0{print $6;}'"
        # strip the \n in filepath
        # TODO: another method to find out the changelog path
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
            self.changelogpath = changelogpath
        else:
            # deb file doesn't contain a changelog,
            self.changelogpath = ''

    def get_changelog(self):
        """Get changelogs of package.
        depends on dpkg-deb, zcat
        return changelogs: str
        """
        if self.changelogpath:
            # create tmp dir
            randomstr = gen_randomstr(10)
            TMPDIR = '/tmp/diffchangelog-' + randomstr

            extractcmd = "dpkg-deb -x " + self.filename + " " + TMPDIR

            extractdeb = os.system(extractcmd)
            # extract deb failed?
            if extractdeb != 0:
                raise "Extract deb file failed."

            zcatcmd = "cd " + TMPDIR + " && zcat " + self.changelogpath

            changelogs = os.popen(zcatcmd).read()

            # clean TMPDIR
            cleancmd = "rm -rf " + TMPDIR
            os.system(cleancmd)

            if changelogs:
                self.changelog = changelogs
        else:
            self.changelog = ''
