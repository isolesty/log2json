#!/bin/bash

return_curl(){
	cmdres=$?
	bash ${script_path}/curl_back.sh checkupdate ${cmdres} ${host_api} ${review_id} ${BUILD_URL} 
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
PPA_TYPE=''

base_name=$(basename ${base})
rpa_name=$(basename ${rpa})
if [ x${rpa_name} == 'x' ]; then
    echo "rpa name not found."
    exit 1
fi
if echo ${rpa_name} | grep debian >/dev/null 2>&1
then
    PPA_TYPE="debian"
fi

# use pools.corp instead of test.pacakges
rpa=${rpa/'http://proposed.packages'/'http://pools.corp'}

script_path="/mnt/mirror-snapshot/utils"
log_path="/mnt/mirror-snapshot/checkupdate-logs"
repo_base="/srv/pool/base"
repo_www="/srv/pool/www"

bash ${script_path}/curl_back.sh start checkupdate ${host_api} ${review_id} ${BUILD_URL} 

# rpa should rebuild itself and changelogs diff
if [ -d "${repo_base}/rpa/${rpa_name}" ] && [ -d "${repo_www}/rpa/${rpa_name}" ]; then

    # use the result.json in rpa
    rpa_base_dir="${repo_base}/rpa/${rpa_name}"
    rpa_www_dir="${repo_www}/rpa/${rpa_name}"

    # rebuild this rpa
    ${script_path}/create_rpa.sh 'update' ${rpa_name} ${host_api} ${review_id}

else
    _date=$(date +%Y-%m-%d~%H%M%S)

    base_dir=""
    www_dir=""

    case $base_name in
        deepin)
            base_dir="/mnt/mirror-snapshot/reprepro-base/deepin-2015-process"
            www_dir="${repo_www}/deepin"
            ;;
        *)
            if [ -d ${repo_base}/${base_name} ] && [ -d ${repo_www}/${base_name} ];then
                base_dir="${repo_base}/${base_name}"
                www_dir="${repo_www}/${base_name}"
            elif [ -d ${repo_base}/ppa/${base_name} ] && [ -d ${repo_www}/ppa/${base_name} ]; then
                base_dir="${repo_base}/ppa/${base_name}"
                www_dir="${repo_www}/ppa/${base_name}"
            fi
            ;;
    esac


    if [ -d ${base_dir} ] && [ -d ${www_dir} ]; then
        echo "repo dir found."
    else
        echo "repo dir not found."
        exit 9
    fi

    _check_log="${log_path}/${base_name}-check-${_date}.log"

    cd ${base_dir}
    rpa_arch=$(/usr/bin/python3 ${script_path}/getrpa.py ${rpa} ${rpa_codename} "Architectures")
    rpa_components=$(/usr/bin/python3 ${script_path}/getrpa.py ${rpa} ${rpa_codename} "Components")


    # rewrite conf/updates
    mv conf/updates conf/updates.orig
    echo "Name: ${rpa_name}" > ${base_dir}/conf/updates
    echo "Suite: ${rpa_codename}" >> ${base_dir}/conf/updates
    echo "Architectures: ${rpa_arch} source" >> ${base_dir}/conf/updates
    echo "Components: ${rpa_components}" >> ${base_dir}/conf/updates
    echo "Method: ${rpa}" >> ${base_dir}/conf/updates
    if [ ${PPA_TYPE} == 'debian' ]; then
        echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
    fi
    echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates

    sed -i "s#Update:.*#Update: ${rpa_name}#"  ${base_dir}/conf/distributions

    cat ${base_dir}/conf/distributions
    cat ${base_dir}/conf/updates

    reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} checkupdate | tee  ${_check_log}
    /usr/bin/python3 ${script_path}/log2json.py ${_check_log}

	mkdir -p ${www_dir}/checkupdate/${_date}
    mkdir -p ${www_dir}/checkupdate/${review_id}
    ln -s ${www_dir}/checkupdate/${_date} ${www_dir}/checkupdate/${review_id}/${_date}
    cp  ${script_path}/index.html ${www_dir}/checkupdate/${_date}/
    mv ${base_dir}/*.json ${www_dir}/checkupdate/${_date}/result.json
fi