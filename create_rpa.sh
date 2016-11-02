#!/bin/bash
set -x
Usage(){
	echo "create_rpa.sh all base_repo_url base_repo_codename ppa_repo_url ppa_repo_codename"
	echo "example:"
	echo "create_rpa.sh all http://packages.deepin.com/deepin unstable http://packages.deepin.com/ppa/debian0311 unstable"
	echo "create_rpa.sh update ppa_name"
	echo "example:"
	echo "create_rpa.sh update 00bea9df4e6c67331d9f79ce61a06983"
}

return_curl(){

    # if [ -f ${base_dir}/conf/updates.orig ]; then
    #     mv ${base_dir}/conf/updates.orig ${base_dir}/conf/updates
    # fi
	
	# conf_dir must be exist
	if [ -d ${conf_dir} ];then
		# no dirs in conf_dir
		cd ${conf_dir} && rm -f ./*
		cd ../ && rmdir ${conf_dir}
	else
		exit 8
	fi
       
}
trap return_curl EXIT

find_dir(){
	base_dir=""
	www_dir=""

	case $base_name in
	    deepin)
	        base_dir=${deepin_base_dir}
	        www_dir=${deepin_www_dir}
	        ;;
	    *)
	        if [ -d ${repo_base}/${base_name} ] && [ -d ${repo_www}/${base_name} ];then
	            base_dir="${repo_base}/${base_name}"
	            www_dir="${repo_www}/${base_name}"
	        elif [ -d ${repo_base}/ppa/${base_name} ] && [ -d ${repo_www}/ppa/${base_name} ]; then
	            base_dir="${repo_base}/ppa/${base_name}"
	            www_dir="${repo_www}/ppa/${base_name}"
	        elif [ -d ${repo_base}/rpa/${base_name} ] && [ -d ${repo_www}/rpa/${base_name} ]; then
	            base_dir="${repo_base}/rpa/${base_name}"
	            www_dir="${repo_www}/rpa/${base_name}"
	            TYPE="rpa"
	        fi
	        ;;
	esac


	if [ -d ${base_dir} ] && [ -d ${www_dir} ]; then
	    echo "repo dir found."
	else
	    echo "repo dir not found."
	    exit 9
	fi
}

# checkupdate start
checkupdate(){
	_check_log=${log_path}/${base_name}-check-${_date}.log

	# create a temp conf dir
	cp -r ${base_dir}/conf ${conf_dir}
	cd ${conf_dir}

	ppa_arch=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Architectures")
	ppa_components=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Components")


	# rewrite updates
	mv updates updates.orig
	echo "Name: ${ppa_name}" > updates
	echo "Suite: ${ppa_codename}" >> updates
	echo "Architectures: ${ppa_arch} source" >> updates
	echo "Components: ${ppa_components}" >> updates
	echo "Method: ${ppa}" >> updates

	if [ x${PPA_TYPE} == 'xdebian' ]; then
		echo "FilterSrcList:install upstreamer.filter" >> updates
	fi
	
	echo "VerifyRelease: blindtrust" >> updates

	sed -i "s#Update:.*#Update: ${ppa_name}#"  distributions

	# cat distributions
	# cat updates

	reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} --confdir ${conf_dir} checkupdate | tee  ${_check_log}
	/usr/bin/python3 ${script_path}/log2json.py ${_check_log} ${base} ${base_codename} ${ppa} ${ppa_codename}

	mkdir -p ${www_dir}/checkupdate/${_date}
	# mkdir -p ${www_dir}/checkupdate/${review_id}
	# ln -s ${www_dir}/checkupdate/${_date} ${www_dir}/checkupdate/${review_id}/${_date}
	cp  ${script_path}/index.html ${www_dir}/checkupdate/${_date}/
	mv ${conf_dir}/*.json ${www_dir}/checkupdate/${_date}/result.json
}
# checkupdate end

create_rpa(){
	rpa_name=$(python3 ${script_path}/newrpa.py ${www_dir}/checkupdate/${_date}/result.json ${ppa})
	if [ x${rpa_name} == 'x' ]; then
		echo "Create new rpa failed."
		exit 9
	else
		echo ${rpa_name}
		# cwd will be deleted
		# cd /tmp && bash ${script_path}/curl_back.sh rpa ${rpa_name} ${host_api} ${review_id}
	fi
}


update_rpa(){
	# change to rpa dir
	rpa_www_dir="${repo_www}/rpa/${rpaname}"
	cd ${rpa_www_dir}
	rpa_name=$(python3 ${script_path}/newrpa.py ${www_dir}/checkupdate/${_date}/result.json ${ppa} ${rpaname})
	if [ x${rpa_name} == 'x' ]; then
		echo "Create new rpa failed."
		exit 9
	else
		echo ${rpa_name}
		# cwd will be deleted
		# cd /tmp && bash ${script_path}/curl_back.sh rpa ${rpa_name} ${host_api} ${review_id}
	fi
}


diff_changelogs(){
	rpa_www_dir="${repo_www}/rpa/${rpa_name}"
	# diffchangelogs.py show all debs in its dir
	cp ${script_path}/diffchangelogs.py ${rpa_www_dir}/pool/

	# changelogs index.html is in rpa base template
	# result.json is in rpa's checkupdate
	# diffchangelogs.py output is data.json
	cd ${rpa_www_dir}/pool && python3 diffchangelogs.py ${rpa_www_dir}/checkupdate/result.json
	mv data.json ${rpa_www_dir}/checkupdate/

	# clean
	rm ${rpa_www_dir}/pool/diffchangelogs.py
}

# added by Choldrim
backup_checkupdate_hist(){
    set -x
    rpa_checkupdate_hist="/tmp/checkupdate_hist/${rpaname}"
    rm -rfv ${rpa_checkupdate_hist}
    mkdir -pv ${rpa_checkupdate_hist}
	rpa_www_dir="${repo_www}/rpa/${rpaname}"
    cp -rv ${rpa_www_dir}/checkupdate ${rpa_checkupdate_hist}/
}


# added by Choldrim
restore_checkupdate_hist(){
    cd ${rpa_checkupdate_hist}/checkupdate/
 
    if [ -f ${patch_set_file_name} ];then
        latest_patch_set=$(cat ${patch_set_file_name})
        for((i=0;i<=${latest_patch_set};i++));do
            cp -rv $i ${rpa_www_dir}/checkupdate
        done
    fi

    cp -v ${patch_set_file_name} ${rpa_www_dir}/checkupdate

    rm -rf ${rpa_checkupdate_hist}

    cd -
}


# added by Choldrim
archive_with_patch_set(){
    echo "start archive data.json with patch set"

    cd ${rpa_www_dir}/checkupdate/

    next_patch_set=0

    # get latest patch set num
    # if latestPatchSet file not found, gen and echo init num into it
    if [ ! -f ${patch_set_file_name} ];then
        echo 0 > ${patch_set_file_name}
    else
        latest_patch_set=$(cat ${patch_set_file_name})
        next_patch_set=$(($latest_patch_set + 1))
    fi

    # archive
    mkdir -pv $next_patch_set
    mv -v data.json $next_patch_set/
    ln -sf $next_patch_set/data.json data.json

    # write back the next patch set num
    echo $next_patch_set  > $patch_set_file_name

    cd -
    set +x
}

merge_rpa(){
	#merge
	cp -r ${base_dir}/conf ${conf_dir}
	cd ${conf_dir}

	ppa_arch=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Architectures")
	ppa_components=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Components")


	# rewrite conf/updates
	mv updates updates.orig
	echo "Name: ${ppa_name}" > updates
	echo "Suite: ${ppa_codename}" >> updates
	echo "Architectures: ${ppa_arch} source" >> updates
	echo "Components: ${ppa_components}" >> updates
	echo "Method: ${ppa}" >> updates

	if [ x${PPA_TYPE} == 'xdebian' ]; then
		echo "FilterSrcList:install upstreamer.filter" >> updates
	fi
	
	echo "VerifyRelease: blindtrust" >> updates

	sed -i "s#Update:.*#Update: ${ppa_name}#"  distributions

	# cat distributions
	# cat updates

	reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} --confdir ${conf_dir} update

	if [[ $? == 0 ]]; then
		# get all result.json
		cd ${www_dir}
		wget ${ppa}/checkupdate/result.json
		# mergejson return a merged json instead of base json
		python3 ${script_path}/mergejson.py checkupdate/result.json result.json
		rpa_name=${base_name}
	else
		exit 8
	fi
}


return_rr(){
	cd /tmp && bash ${script_path}/curl_back.sh rpa ${rpa_name} ${host_api} ${review_id} ${BUILD_URL}
}


find_rpa(){
	# a rpa has only one result.json
	old_rpa=$(find ${repo_www}/rpa -ctime -3 -name 'result.json' -exec grep -H ${ppa} {} \; | awk -F : '{print $1}')
	# a related rpa exist
	if [[ x${old_rpa} != 'x' ]]; then
		# result_json example: /srv/pool/www/rpa/984131bd34b0f3c55da465a5d13850e8/checkupdate/result.json
		result_json=(${old_rpa//// })
		rpa_name=${result_json[4]}
		return_rr || exit 1
		exit 0
	fi

}

# new.sh all base_repo_url base_repo_codename ppa_repo_url ppa_repo_codename
# example:
# new.sh all http://packages.deepin.com/deepin unstable http://packages.deepin.com/ppa/debian0311 unstable
_date=$(date +%Y-%m-%d~%H%M%S)

script_path="/mnt/mirror-snapshot/utils"
log_path="/mnt/mirror-snapshot/checkupdate-logs"
repo_base="/srv/pool/base"
repo_www="/srv/pool/www"
deepin_base_dir="/mnt/mirror-snapshot/reprepro-base/deepin-2015-process"
deepin_www_dir="${repo_www}/deepin"
PPA_TYPE=''
TYPE=''
review_id=''
host_api=''
conf_dir=''
patch_set_file_name='latestPatchSet'


if [[ $1 == 'all' ]]; then
	base=$2
	base_codename=$3
	ppa=$4
	ppa_codename=$5
	
	if [[ $# == 8 ]];then
		host_api=$6
		review_id=$7
		BUILD_URL=$8
	fi
	

	base_name=$(basename ${base})
	ppa_name=$(basename ${ppa})
	if echo ${ppa_name} | grep debian >/dev/null 2>&1
	then
		PPA_TYPE="debian"
	fi
	conf_dir="/tmp/create-${base_name}-${ppa_name}-${_date}"
#	mkdir ${conf_dir}

	find_rpa

	find_dir || exit 1
	if [[ ${TYPE} == "rpa" ]]; then
		merge_rpa || exit 1
	else
		checkupdate || exit 1
		create_rpa || exit 1	
	fi
	diff_changelogs || exit 1
    
    if [[ $# == 8 ]];then
    	archive_with_patch_set || exit 1
    	return_rr || exit 1
    fi

elif [[ $1 == 'update' ]]; then
	rpaname=$2
	if [[ $# == 4 ]];then
		host_api=$3
		review_id=$4
	fi
	if [ x${rpaname} == 'x' ]; then
    	echo "rpa name not found."
    	exit 2
	fi
	# result.json must be stored in this path
	jsonfile="${repo_www}/rpa/${rpaname}/checkupdate/result.json"
	base=$(python3 ${script_path}/parserjson.py ${jsonfile} 'base')
	base_codename=$(python3 ${script_path}/parserjson.py ${jsonfile} 'basecodename')
	ppa=$(python3 ${script_path}/parserjson.py ${jsonfile} 'update')
	ppa_codename=$(python3 ${script_path}/parserjson.py ${jsonfile} 'updatecodename')

	base_name=$(basename ${base})
	ppa_name=$(basename ${ppa})

	if echo ${ppa_name} | grep debian >/dev/null 2>&1
	then
		PPA_TYPE="debian"
	fi
	conf_dir="/tmp/create-${base_name}-${ppa_name}-${_date}"
	#mkdir ${conf_dir}

    backup_checkupdate_hist || exit 1
	find_dir || exit 1
	checkupdate || exit 1
	update_rpa || exit 1
	diff_changelogs || exit 1
    restore_checkupdate_hist || exit 1
    archive_with_patch_set || exit 1
	return_rr || exit 1
else
	Usage
fi
