cleanup() {
	rm -rf -- "$temporary_dir"
	[[ -z $metadata_temporary ]] || rm -f -- "$metadata_temporary"
}

terminate() {
	local status=$1

	trap - HUP INT TERM
	if [[ -n $request_pid ]]; then
		kill -TERM "$request_pid" 2>/dev/null || true
		wait "$request_pid" 2>/dev/null || true
	fi
	exit "$status"
}

send_destiny_request() {
	local request_status=0

	if [[ -f /etc/xcat/cert.pem && -f /etc/xcat/certkey.pem ]]; then
		openssl s_client -key /etc/xcat/certkey.pem \
			-cert /etc/xcat/cert.pem -connect "$destination" -quiet \
			2>/dev/null <"$request_file" >"$response_file" &
	else
		openssl s_client -connect "$destination" -quiet \
			2>/dev/null <"$request_file" >"$response_file" &
	fi
	request_pid=$!
	wait "$request_pid" || request_status=$?
	request_pid=
	return "$request_status"
}

extract_element() {
	local element=$1

	sed -n "s:.*<$element>\([^<]*\)</$element>.*:\1:p" "$response_file" \
		| head -n 1 | tr -cd '\40-\176'
}

write_metadata() {
	local command=$1 metadata_dir

	metadata_dir=${metadata_file%/*}
	if [[ $metadata_dir == "$metadata_file" ]]; then
		metadata_dir=.
	elif [[ -z $metadata_dir ]]; then
		metadata_dir=/
	fi
	[[ -d $metadata_dir ]] || exit 1
	metadata_temporary=$(mktemp "$metadata_dir/.$command.XXXXXX") || exit 1
	{
		printf 'XCAT_NODE_NAME=%s\n' "$(extract_element name)"
		printf 'XCAT_DESTINY=%s\n' "$destiny"
		printf 'XCAT_IMAGE_SERVER=%s\n' "$(extract_element imgserver)"
		printf 'XCAT_KERNEL=%s\n' "$(extract_element kernel)"
		printf 'XCAT_INITRD=%s\n' "$(extract_element initrd)"
		printf 'XCAT_KERNEL_COMMAND_LINE=%s\n' "$(extract_element kcmdline)"
	} >"$metadata_temporary"
	chmod 0600 "$metadata_temporary"
	mv -f -- "$metadata_temporary" "$metadata_file"
}
