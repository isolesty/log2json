#!/usr/bin/env python3

import re
import sys
import json

if __name__ == '__main__':
    """checkupdate log to json
    include file url, exclude arch
    """
    poolfilere = re.compile(" files needed:(.+)")
    archre = re.compile(" files needed:.+_.+_(.+).deb")
    sourcere = re.compile(" files needed:.+.dsc.*")
    newre = re.compile("'(.+)': newly installed as '(.+)' \(from '(.+)'\):")
    updatere = re.compile(
        "'(.+)': '(.+)' will be upgraded to '(.+)' \(from '(.+)'\):")
    lognamere = re.compile(".+(\d\d\d\d-\d\d-\d\d~\d\d\d\d\d\d).log")

    newdeb = []
    updatedeb = []

    if len(sys.argv) > 1:
        resultlog = sys.argv[1]

        with open(resultlog, 'r') as f:
            logfile = f.readlines()

        filelen = len(logfile)
        x = 0
        while x < filelen:
            # example:
            # Updates needed for 'unstable|non-free|source':
            if logfile[x].startswith('Updates'):
                pass
            else:
                # examples: (words wrap , files needed: should be the same line of pool/xxx )
                # 'linux-manual-4.4': newly installed as '4.4.4-2' (from 'debian'):
                # files needed:
                # pool/main/l/linux/linux-manual-4.4_4.4.4-2_all.deb
                # 'nvidia-cuda-mps': '352.79-2+deepin' will be upgraded to '352.79-5' (from 'debian'):
                # files needed:
                # pool/non-free/n/nvidia-graphics-drivers/nvidia-cuda-mps_352.79-5_amd64.deb
                baseline = logfile[x]
                fileline = logfile[x + 1]

                if 'newly' in baseline:
                    # confirm the next two lines is one source
                    x += 1
                    debdata = newre.findall(baseline)[0]
                    debname = debdata[0]
                    debnewversion = debdata[1]
                    debrepo = debdata[2]
                    deburl = poolfilere.findall(fileline)[0].strip().split(' ')
                    debarch = 'unknown'
                    if sourcere.findall(fileline):
                        debarch = 'source'
                    elif archre.findall(fileline):
                        debarch = archre.findall(fileline)[0]

                    tojson = {
                        'name': debname,
                        'type': 'add',
                        "arch": debarch,
                        'oldversion': '0',
                        'newversion': debnewversion,
                        'repo': debrepo,
                        'filelist': deburl}
                    # multi arch have same _all.deb
                    if tojson in newdeb:
                        pass
                    else:
                        newdeb.append(tojson)

                elif 'upgraded' in baseline:
                    # confirm the next two lines is one source
                    x += 1
                    debdata = updatere.findall(baseline)[0]
                    debname = debdata[0]
                    deboldversion = debdata[1]
                    debnewversion = debdata[2]
                    debrepo = debdata[3]
                    deburl = poolfilere.findall(fileline)[0].strip().split(' ')
                    debarch = 'unknown'
                    if sourcere.findall(fileline):
                        debarch = 'source'
                    elif archre.findall(fileline):
                        debarch = archre.findall(fileline)[0]

                    tojson = {
                        'name': debname,
                        'type': 'update',
                        "arch": debarch,
                        'oldversion': deboldversion,
                        'newversion': debnewversion,
                        'repo': debrepo,
                        'filelist': deburl}
                    # multi arch have same _all.deb
                    if tojson in updatedeb:
                        pass
                    else:
                        updatedeb.append(tojson)
                else:
                    # some unknown lines, such as blank
                    pass

            x += 1

        time = lognamere.findall(resultlog)[0]
        resultjson = {'time': time, 'details': newdeb + updatedeb}
        with open(time + '.json', 'w') as f:
            json.dump(resultjson, f)
