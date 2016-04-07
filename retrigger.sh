#!/bin/bash

return_curl(){
	cmdres=$?
	bash /mnt/mirror-snapshot/utils/curl_back.sh checkupdate ${cmdres} ${host_api} ${review_id} ${BUILD_URL} 
    if [ -f ${base_dir}/conf/updates.orig ]; then
        mv ${base_dir}/conf/updates.orig ${base_dir}/conf/updates
    fi
}
trap return_curl EXIT


source params.env

review_id=${REVIEW_ID}
base=${BASE}
base_codename=${BASE_CODENAME}
rpa=${RPA}
rpa_codename=${RPA_CODENAME}
host_api=${HOST_API}

base_name=$(basename ${base})
rpa_name=$(basename ${rpa})
# use pools.corp instead of test.pacakges
rpa=${rpa/'http://proposed.packages'/'http://pools.corp'}


# rpa should rebuild itself and changelogs diff
if [ -d "/srv/pool/base/rpa/${rpa_name}" ] && [ -d "/srv/pool/www/rpa/${rpa_name}" ]; then

    # use the result.json in rpa
    rpa_base_dir="/srv/pool/base/rpa/${rpa_name}"
    rpa_www_dir="/srv/pool/www/rpa/${rpa_name}"

    # rebuild this rpa
    /mnt/mirror-snapshot/utils/create_rpa.sh 'update' ${rpa_name} ${rpa_www_dir}/checkupdate/result.json

else
    _date=$(date +%Y-%m-%d~%H%M%S)

    base_dir=""
    www_dir=""

    case $base_name in
        deepin)
            base_dir="/mnt/mirror-snapshot/reprepro-base/deepin-2015-process"
            www_dir="/srv/pool/www/deepin"
            ;;
        *)
            if [ -d /srv/pool/base/${base_name} ] && [ -d /srv/pool/www/${base_name} ];then
                base_dir="/srv/pool/base/${base_name}"
                www_dir="/srv/pool/www/${base_name}"
            elif [ -d /srv/pool/base/ppa/${base_name} ] && [ -d /srv/pool/www/ppa/${base_name} ]; then
                base_dir="/srv/pool/base/ppa/${base_name}"
                www_dir="/srv/pool/www/ppa/${base_name}"
            fi
            ;;
    esac


    if [ -d ${base_dir} ] && [ -d ${www_dir} ]; then
        echo "repo dir found."
    else
        echo "repo dir not found."
        exit 9
    fi

    _check_log=/mnt/mirror-snapshot/checkupdate-logs/${base_name}-check-${_date}.log

    cd ${base_dir}
    rpa_arch=$(/usr/bin/python3 /mnt/mirror-snapshot/utils/getrpa.py ${rpa} ${rpa_codename} "Architectures")
    rpa_components=$(/usr/bin/python3 /mnt/mirror-snapshot/utils/getrpa.py ${rpa} ${rpa_codename} "Components")


    # rewrite conf/updates
    mv conf/updates conf/updates.orig
    echo "Name: ${rpa_name}" > ${base_dir}/conf/updates
    echo "Suite: ${rpa_codename}" >> ${base_dir}/conf/updates
    echo "Architectures: ${rpa_arch} source" >> ${base_dir}/conf/updates
    echo "Components: ${rpa_components}" >> ${base_dir}/conf/updates
    echo "Method: ${rpa}" >> ${base_dir}/conf/updates
    echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
    echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates

    sed -i "s#Update:.*#Update: ${rpa_name}#"  ${base_dir}/conf/distributions

    cat ${base_dir}/conf/distributions
    cat ${base_dir}/conf/updates

    reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} checkupdate | tee  ${_check_log}
    /usr/bin/python3 /mnt/mirror-snapshot/utils/log2json.py ${_check_log}

	mkdir -p ${www_dir}/checkupdate/${_date}
    mkdir -p ${www_dir}/checkupdate/${review_id}
    ln -s ${www_dir}/checkupdate/${_date} ${www_dir}/checkupdate/${review_id}/${_date}
    cp  /mnt/mirror-snapshot/utils/index.html ${www_dir}/checkupdate/${_date}/
    mv ${base_dir}/*.json ${www_dir}/checkupdate/${_date}/result.json
fi