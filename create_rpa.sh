#!/bin/bash

Usage(){
	echo "new.sh all base_repo_url base_repo_codename ppa_repo_url ppa_repo_codename"
	echo "example:"
	echo "new.sh all http://packages.deepin.com/deepin unstable http://packages.deepin.com/ppa/debian0311 unstable"
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
	        elif [ -d /srv/pool/base/rpa/${base_name} ] && [ -d /srv/pool/www/rpa/${base_name} ]; then
	            base_dir="/srv/pool/base/rpa/${base_name}"
	            www_dir="/srv/pool/www/rpa/${base_name}"
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
	_check_log=/mnt/mirror-snapshot/checkupdate-logs/${base_name}-check-${_date}.log

	cd ${base_dir}

	ppa_arch=$(/usr/bin/python3 /mnt/mirror-snapshot/utils/getrpa.py ${ppa} ${ppa_codename} "Architectures")
	ppa_components=$(/usr/bin/python3 /mnt/mirror-snapshot/utils/getrpa.py ${ppa} ${ppa_codename} "Components")


	# rewrite conf/updates
	mv conf/updates conf/updates.orig
	echo "Name: ${ppa_name}" > ${base_dir}/conf/updates
	echo "Suite: ${ppa_codename}" >> ${base_dir}/conf/updates
	echo "Architectures: ${ppa_arch} source" >> ${base_dir}/conf/updates
	echo "Components: ${ppa_components}" >> ${base_dir}/conf/updates
	echo "Method: ${ppa}" >> ${base_dir}/conf/updates
	echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
	echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates

	sed -i "s#Update:.*#Update: ${ppa_name}#"  ${base_dir}/conf/distributions

	cat ${base_dir}/conf/distributions
	cat ${base_dir}/conf/updates

	reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} checkupdate | tee  ${_check_log}
	/usr/bin/python3 /mnt/mirror-snapshot/utils/log2json.py ${_check_log} ${base} ${base_codename} ${ppa} ${ppa_codename}

	mkdir -p ${www_dir}/checkupdate/${_date}
	# mkdir -p ${www_dir}/checkupdate/${review_id}
	# ln -s ${www_dir}/checkupdate/${_date} ${www_dir}/checkupdate/${review_id}/${_date}
	cp  /mnt/mirror-snapshot/utils/index.html ${www_dir}/checkupdate/${_date}/
	mv ${base_dir}/*.json ${www_dir}/checkupdate/${_date}/result.json
}
# checkupdate end

create_rpa(){
	rpa_name=$(python3 /mnt/mirror-snapshot/utils/newrpa.py ${www_dir}/checkupdate/${_date}/result.json ${ppa})
	if [ x${rpa_name} == 'x' ]; then
		echo "Create new rpa failed."
		exit 9
	else
		echo ${rpa_name}
	fi
}


update_rpa(){
	rpa_name=$(python3 /mnt/mirror-snapshot/utils/newrpa.py ${www_dir}/checkupdate/${_date}/result.json ${ppa} ${rpaname})
	if [ x${rpa_name} == 'x' ]; then
		echo "Create new rpa failed."
		exit 9
	else
		echo ${rpa_name}
	fi
}


diff_changelogs(){
	rpa_www_dir="/srv/pool/www/rpa/${rpa_name}"
	# diffchangelogs.py show all debs in its dir
	cp /mnt/mirror-snapshot/utils/diffchangelogs.py ${rpa_www_dir}/pool/

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

	ppa_arch=$(/usr/bin/python3 /mnt/mirror-snapshot/utils/getrpa.py ${ppa} ${ppa_codename} "Architectures")
	ppa_components=$(/usr/bin/python3 /mnt/mirror-snapshot/utils/getrpa.py ${ppa} ${ppa_codename} "Components")


	# rewrite conf/updates
	mv conf/updates conf/updates.orig
	echo "Name: ${ppa_name}" > ${base_dir}/conf/updates
	echo "Suite: ${ppa_codename}" >> ${base_dir}/conf/updates
	echo "Architectures: ${ppa_arch} source" >> ${base_dir}/conf/updates
	echo "Components: ${ppa_components}" >> ${base_dir}/conf/updates
	echo "Method: ${ppa}" >> ${base_dir}/conf/updates
	echo "FilterSrcList:install upstreamer.filter" >> ${base_dir}/conf/updates
	echo "VerifyRelease: blindtrust" >> ${base_dir}/conf/updates

	sed -i "s#Update:.*#Update: ${ppa_name}#"  ${base_dir}/conf/distributions

	cat ${base_dir}/conf/distributions
	cat ${base_dir}/conf/updates

	reprepro --noskipold --basedir ${base_dir} --outdir ${www_dir} update

	if [[ $? == 0 ]]; then
		# get all result.json
		cd ${www_dir}
		wget ${ppa}/checkupdate/result.json
		# mergejson return a merged json instead of base json
		python3 /mnt/mirror-snapshot/utils/mergejson.py checkupdate/result.json result.json
		rpa_name=${base_name}
	else
		exit 8
	fi
}

# new.sh all base_repo_url base_repo_codename ppa_repo_url ppa_repo_codename
# example:
# new.sh all http://packages.deepin.com/deepin unstable http://packages.deepin.com/ppa/debian0311 unstable
if [[ $1 == 'all' ]]; then
	base=$2
	base_codename=$3
	ppa=$4
	ppa_codename=$5
	TYPE=''

	base_name=$(basename ${base})
	ppa_name=$(basename ${ppa})

	_date=$(date +%Y-%m-%d~%H%M%S)

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
	jsonfile=$3
	base=$(python3 /mnt/mirror-snapshot/utils/parserjson.py ${jsonfile} 'base')
	base_codename=$(python3 /mnt/mirror-snapshot/utils/parserjson.py ${jsonfile} 'basecodename')
	ppa=$(python3 /mnt/mirror-snapshot/utils/parserjson.py ${jsonfile} 'update')
	ppa_codename=$(python3 /mnt/mirror-snapshot/utils/parserjson.py ${jsonfile} 'updatecodename')

	find_dir || exit 1
	update_rpa || exit 1
else
	Usage
fi