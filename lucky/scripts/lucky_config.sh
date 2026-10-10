#!/bin/sh

source /koolshare/scripts/base.sh
eval $(dbus export lucky_)
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
LOG_FILE=/tmp/upload/lucky_log.txt
LUCKY_LOG_FILE=/tmp/upload/lucky.log
LOCK_FILE=/var/lock/lucky.lock
BASH=${0##*/}
ARGS=$@

set_lock(){
	exec 999>${LOCK_FILE}
	flock -n 999 || {
		# bring back to original log
		http_response "$ACTION"
		exit 1
	}
}

unset_lock(){
	flock -u 999
	rm -rf ${LOCK_FILE}
}

number_test(){
	case $1 in
		''|*[!0-9]*)
			echo 1
			;;
		*)
			echo 0
			;;
	esac
}

detect_running_status(){
	local BINNAME=$1
	local PID
	local i=40
	until [ -n "${PID}" ]; do
		usleep 250000
		i=$(($i - 1))
		PID=$(pidof ${BINNAME})
		if [ "$i" -lt 1 ]; then
			echo_date "🔴$1进程启动失败，请检查你的配置！"
			return
		fi
	done
	echo_date "🟢Lucky 启动成功，pid：${PID}"
}

check_status(){
	local LUCKY_PID=$(pidof lucky)
	if [ "${lucky_enable}" == "1" ]; then
		if [ -n "${LUCKY_PID}" ]; then
			local ret="Lucky 进程运行正常！（PID：${LUCKY_PID}）"
		else
			local ret="Lucky 进程未运行！"
		fi
	else
		local ret="Lucky 插件未启用"
	fi
	http_response "$ret"
}

close_lucky_process(){
	local lucky_process=$(pidof lucky)
	if [ -n "${lucky_process}" ]; then
		echo_date "⛔关闭Lucky进程..."
		killall lucky >/dev/null 2>&1
		kill -9 "${lucky_process}" >/dev/null 2>&1
		rm -rf /var/run/lucky.pid /tmp/var/lucky.pid /tmp/lucky.pid /koolshare/perp/lucky
	fi
}

start_lucky_process(){
	rm -rf ${LUCKY_LOG_FILE}
	echo_date "🟠启动 Lucky 进程..."
	rm -rf /var/run/lucky.pid /tmp/var/lucky.pid /tmp/lucky.pid

	# 1. 提升最大文件句柄限制，保障大流量穿透与反向代理连接不掉线 (杜绝 Too many open files)
	ulimit -n 65535 2>/dev/null || ulimit -n 4096 2>/dev/null

	# 2. 内存调优参数：限制 Go 运行时内存上限并积极释放物理内存
	export GOMEMLIMIT=24MiB
	export GODEBUG=madvdontneed=1

	start-stop-daemon -S -q -b -m -p /var/run/lucky.pid -x /koolshare/bin/lucky -- -cd /koolshare/configs/lucky/
	sleep 1
	detect_running_status lucky
}

read_version() {
	# 获取lucky info
	info=$(lucky -info)

	# 解析版本号
	version=$(echo $info | grep -o '"Version":"[^"]*"' | sed 's/"Version":"\([^"]*\)"/\1/')
	
	# 检查是否成功提取版本号
	if [ -z "$version" ]; then
		echo_date "❌获取Lucky内核版本号，请稍后重试."
		return 1
	else
		echo_date "🍭Lucky内核版本号为：$version"
		dbus set lucky_binary="$version"
	fi
}

read_base_info() {
	# 获取lucky baseinfo
	baseConfInfo=$(lucky -cd /koolshare/configs/lucky -baseConfInfo)

	# 解析端口号
	lucky_port=$(echo "$baseConfInfo" | grep -o '"AdminWebListenPort":[0-9]*' | sed 's/"AdminWebListenPort"://')
	# 解析安全路径
	lucky_safeurl=$(echo "$baseConfInfo" | grep -o '"SafeURL":"[^"]*"' | sed 's/"SafeURL":"\([^"]*\)"/\1/')

	# 检查是否成功提取端口号
	if [ -z "$lucky_port" ]; then
		echo "❌获取Lucky端口失败，请稍后重试."
		return 1
	else
		echo_date "🍭Lucky端口号为：$lucky_port"
		dbus set lucky_port="$lucky_port"
		dbus set lucky_safeurl="$lucky_safeurl"
	fi
}

reset_param() {
	# 检查进程是否存在
	if pidof lucky > /dev/null; then
		# 初始化命令
		command="lucky -cd /koolshare/configs/lucky"

		# 根据 dbus 参数值拼接命令选项
		if [ "${lucky_reset_safeurl}" -eq 1 ]; then
			command="$command -rCancelSafeURL"
			echo_date "🔸取消安全入口"
		fi

		if [ "${lucky_reset_user}" -eq 1 ]; then
			command="$command -rResetUser"
			echo_date "🔸重置用户账号密码"
		fi

		if [ "${lucky_reset_port}" -eq 1 ]; then
			command="$command -rSetHttpAdminPort 16601 -rSetHttpsAdminPort 16601"
			echo_date "🔸重置后台Http(s)访问端口"
		fi

		if [ "${lucky_reset_disable}" -eq 1 ]; then
			command="$command -rDisable2FA"
			echo_date "🔸禁用2FA验证"
		fi

		# 执行命令
		if [ "$command" != "lucky" ]; then
			echo_date "执行命令: $command"
			eval $command
		fi
		echo_date "✅Lucky 重置成功."
		dbus set lucky_reset_safeurl="0"
		dbus set lucky_reset_user="0"
		dbus set lucky_reset_port="0"
		dbus set lucky_reset_disable="0"
	else
		echo_date "⛔️Lucky 进程未运行，请重启后再试."
		dbus set lucky_reset_safeurl="0"
		dbus set lucky_reset_user="0"
		dbus set lucky_reset_port="0"
		dbus set lucky_reset_disable="0"
	fi
}

close_lucky(){
	# 1. remove and limit log
	rm -rf ${LUCKY_LOG_FILE}
	[ -f "${LOG_FILE}" ] && [ $(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0) -gt 102400 ] && tail -n 200 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"

	# 2. stop 
	close_lucky_process
}

start_lucky(){
	# 1. stop first
	close_lucky_process

	# 2. 检查版本号
	read_version
	sleep 1

	# 3. 读取端口
	read_base_info
	sleep 1

	# 4. start process
	start_lucky_process
}

case $1 in
start)
	if [ "${lucky_enable}" == "1" ]; then
		logger "[软件中心-开机自启]: Lucky开始自动启动！"
		start_lucky
	else
		logger "[软件中心-开机自启]: Lucky未开启，不自动启动！"
	fi
	;;
boot_up)
	if [ "${lucky_enable}" == "1" ]; then
		start_lucky | tee -a ${LOG_FILE}
	fi
	;;
start_nat)
	if [ "${lucky_enable}" == "1" ]; then
		logger "[软件中心]-[${0##*/}]: NAT重启触发重新启动Lucky！"
		lucky -cd /koolshare/configs/lucky -rRestart
	fi
	;;	
stop)
	close_lucky
	;;
esac

case $2 in
web_submit)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	if [ "${lucky_enable}" == "1" ]; then
		echo_date "▶️开启Lucky！" | tee -a ${LOG_FILE}
		start_lucky | tee -a ${LOG_FILE}
	elif [ "${lucky_enable}" == "2" ]; then
		echo_date "🔁重启Lucky！" | tee -a ${LOG_FILE}
		dbus set lucky_enable=1
		start_lucky | tee -a ${LOG_FILE}
	elif [ "${lucky_enable}" == "3" ]; then
		echo_date "🔄开始重置Lucky设置！" | tee -a ${LOG_FILE}
		reset_param | tee -a ${LOG_FILE}
		dbus set lucky_enable=1
	else
		echo_date "ℹ️停止Lucky！" | tee -a ${LOG_FILE}
		close_lucky | tee -a ${LOG_FILE}
	fi
	echo DD01N05S | tee -a ${LOG_FILE}
	unset_lock
	;;
status)
	check_status
	;;
esac
