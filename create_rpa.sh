#!/bin/bash

Usage(){
	echo "create_rpa.sh all base_repo_url base_repo_codename ppa_repo_url ppa_repo_codename"
	echo "example:"
	echo "create_rpa.sh all http://packages.deepin.com/deepin unstable http://packages.deepin.com/ppa/debian0311 unstable"
	echo "create_rpa.sh update ppa_name"
	echo "example:"
	echo "create_rpa.sh update 00bea9df4e6c67331d9f79ce61a06983"
}

return_curl(){

    if [ -f ${base_dir}/conf/updates.orig ]; then
        mv ${base_dir}/conf/updates.orig ${base_dir}/conf/updates
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

	cd ${base_dir}

	ppa_arch=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Architectures")
	ppa_components=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Components")


	# rewrite conf/updates
	mv conf/updates conf/updates.orig
	echo "Name: ${ppa_name}" > ${base_dir}/conf/updates
	echo "Suite: ${ppa_codename}" >> ${base_dir}/conf/updates
	echo "Architectures: ${ppa_arch} source" >> ${base_dir}/conf/updates
	echo "Components: ${ppa_components}" >> ${base_dir}/conf/updates
	echo "Method: ${ppa}" >> ${base_dir}/conf/updates

	if [ x${PPA_TYPE} == 'xdebian' ]; then
		echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
	fi
	
	echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates

	sed -i "s#Update:.*#Update: ${ppa_name}#"  ${base_dir}/conf/distributions

	# cat ${base_dir}/conf/distributions
	# cat ${base_dir}/conf/updates

	reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} checkupdate | tee  ${_check_log}
	/usr/bin/python3 ${script_path}/log2json.py ${_check_log} ${base} ${base_codename} ${ppa} ${ppa_codename}

	mkdir -p ${www_dir}/checkupdate/${_date}
	# mkdir -p ${www_dir}/checkupdate/${review_id}
	# ln -s ${www_dir}/checkupdate/${_date} ${www_dir}/checkupdate/${review_id}/${_date}
	cp  ${script_path}/index.html ${www_dir}/checkupdate/${_date}/
	mv ${base_dir}/*.json ${www_dir}/checkupdate/${_date}/result.json
}
# checkupdate end

create_rpa(){
	rpa_name=$(python3 ${script_path}/newrpa.py ${www_dir}/checkupdate/${_date}/result.json ${ppa})
	if [ x${rpa_name} == 'x' ]; then
		echo "Create new rpa failed."
		exit 9
	else
		echo ${rpa_name}
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


merge_rpa(){
	#merge
	cd ${base_dir}

	ppa_arch=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Architectures")
	ppa_components=$(/usr/bin/python3 ${script_path}/getrpa.py ${ppa} ${ppa_codename} "Components")


	# rewrite conf/updates
	mv conf/updates conf/updates.orig
	echo "Name: ${ppa_name}" > ${base_dir}/conf/updates
	echo "Suite: ${ppa_codename}" >> ${base_dir}/conf/updates
	echo "Architectures: ${ppa_arch} source" >> ${base_dir}/conf/updates
	echo "Components: ${ppa_components}" >> ${base_dir}/conf/updates
	echo "Method: ${ppa}" >> ${base_dir}/conf/updates

	if [ x${PPA_TYPE} == 'xdebian' ]; then
		echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
	fi
	
	echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates

	sed -i "s#Update:.*#Update: ${ppa_name}#"  ${base_dir}/conf/distributions

	# cat ${base_dir}/conf/distributions
	# cat ${base_dir}/conf/updates

	reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} update

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

if [[ $1 == 'all' ]]; then
	base=$2
	base_codename=$3
	ppa=$4
	ppa_codename=$5
	

	base_name=$(basename ${base})
	ppa_name=$(basename ${ppa})
	if echo ${ppa_name} | grep debian >/dev/null 2>&1
	then
		PPA_TYPE="debian"
	fi

	
	find_dir || exit 1
	if [[ ${TYPE} == "rpa" ]]; then
		merge_rpa || exit 1
	else
		checkupdate || exit 1
		create_rpa || exit 1	
	fi
	diff_changelogs || exit 1
elif [[ $1 == 'update' ]]; then
	rpaname=$2
	if [ x${rpaname} == 'x' ]; then
    	echo "rpa name not found."
    	exit 1
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

	find_dir || exit 1
	checkupdate || exit 1
	update_rpa || exit 1
	diff_changelogs || exit 1
else
	Usage
fi