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
# use pools.corp instead of test.pacakges
rpa=${rpa/'http://proposed.packages'/'http://pools.corp'}
if [ x${rpa_name} == 'x' ]; then
    echo "rpa name not found."
    exit 1
fi
if echo ${rpa_name} | grep debian >/dev/null 2>&1
then
    PPA_TYPE="debian"
fi

script_path="/mnt/mirror-snapshot/utils"
log_path="/mnt/mirror-snapshot/merge-logs"
repo_base="/srv/pool/base"
repo_www="/srv/pool/www"


bash ${script_path}/curl_back.sh start merge ${host_api} ${review_id} ${BUILD_URL} 

return_curl(){
    cmdres=$?
    bash ${script_path}/curl_back.sh merge ${cmdres} ${host_api} ${review_id} ${BUILD_URL} 
    if [ -f ${base_dir}/conf/updates.orig ]; then
        mv ${base_dir}/conf/updates.orig ${base_dir}/conf/updates
    fi
}
trap return_curl EXIT

case $base_name in
    deepin)
    	base_dir="/mnt/mirror-snapshot/reprepro-base/deepin-2015-process"
        www_dir="/srv/pool/www/deepin"
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
        echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates
        if [ ${PPA_TYPE} == 'debian' ]; then
            echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
        fi
        sed -i "s#Update:.*#Update: ${rpa_name}#"  ${base_dir}/conf/distributions

        cat ${base_dir}/conf/distributions
        cat ${base_dir}/conf/updates
        
        cd ${script_path} && sudo ./update-deepin-2015_new.sh update ${rpa_name}
        ;;
    *)
        
        _date=$(date +%Y-%m-%d~%H%M%S)

        base_dir=''
        www_dir=''

        if [ -d ${repo_base}/${base_name} ] && [ -d ${repo_www}/${base_name} ];then
            base_dir="${repo_base}/${base_name}"
            www_dir="${repo_www}/${base_name}"
        elif [ -d ${repo_base}/ppa/${base_name} ] && [ -d ${repo_www}/ppa/${base_name} ]; then
            base_dir="${repo_base}/ppa/${base_name}"
            www_dir="${repo_www}/ppa/${base_name}"
        else
            echo "base_dir not found."
            exit 9
        fi

        _merge_log=${log_path}/${base_name}-merge-${_date}.log

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
        echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates
        if [ ${PPA_TYPE} == 'debian' ]; then
            echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
        fi
        sed -i "s#Update:.*#Update: ${rpa_name}#"  ${base_dir}/conf/distributions

        cat ${base_dir}/conf/distributions
        cat ${base_dir}/conf/updates

        set +e
        reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} update >${_merge_log} 2>&1

        # copy merge log to website
        mkdir -p ${www_dir}/update/${review_id}
        cp ${_merge_log} ${www_dir}/update/${review_id}/
        
        # merge failed?
        cat ${_merge_log}
        cat ${_merge_log} | grep 'There have been errors'
        ret=$?
        set -e
        
        if [[ ${ret} == 0 ]]; then
            exit 1
        else
            exit 0
        fi
        ;;
esac