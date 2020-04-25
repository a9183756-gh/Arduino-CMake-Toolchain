#!/bin/sh

_result_dir="$1"
shift

"$@"
ret_code=$?
if [ -f "${_result_dir}/result.txt" ] ; then
	grep -q "Skipped" "${_result_dir}/result.txt"
	if [ $? -eq 0 ]  ; then
		ret_code=100
	fi
fi
exit $ret_code
