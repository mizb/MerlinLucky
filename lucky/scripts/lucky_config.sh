#!/bin/sh

source /koolshare/scripts/base.sh
eval $(dbus export lucky_)
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
LOG_FILE=/tmp/upload/lucky_log.txt
LUCKY_LOG_FILE=/tmp/upload/lucky.log
LOCK_FILE=/var/lock/lucky.lock
LUCKY_BIN=/koolshare/bin/lucky
CONFIG_DIR=/koolshare/configs/lucky
BASH=${0##*/}
ARGS=$@

set_lock(){
	exec 999>${LOCK_FILE}
	flock -n 999 || {
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
	local BINNAME=lucky
	local PID
	local i=40
	until [ -n "${PID}" ]; do
		usleep 250000
		i=$(($i - 1))
		PID=$(pidof ${BINNAME})
		if [ "$i" -lt 1 ]; then
			echo_date "🔴Lucky 进程启动失败，请检查你的配置！"
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
	[ $(cat /proc/sys/fs/file-max 2>/dev/null || echo 0) -lt 1048576 ] && sysctl -w fs.file-max=1048576 >/dev/null 2>&1

	# 2. 内存调优参数：限制 Go 运行时内存上限并积极释放物理内存
	export GOMEMLIMIT=64MiB
	export GODEBUG=madvdontneed=1

	start-stop-daemon -S -q -b -m -p /var/run/lucky.pid -x ${LUCKY_BIN} -- -cd ${CONFIG_DIR}/
	sleep 1
	detect_running_status
}

read_version() {
	if [ ! -x "${LUCKY_BIN}" ]; then
		echo_date "❌未找到可执行文件 ${LUCKY_BIN}"
		return 1
	fi
	local info=$(${LUCKY_BIN} -info 2>&1)
	local version=$(echo "$info" | grep -o '"Version":"[^"]*"' | sed 's/"Version":"\([^"]*\)"/\1/')
	
	if [ -z "$version" ]; then
		version=$(cat /koolshare/lucky/version 2>/dev/null || cat /koolshare/res/version 2>/dev/null || echo "3.3.3")
	fi
	echo_date "🍭Lucky内核版本号为：$version"
	dbus set lucky_binary="$version"
	dbus set lucky_version="$version"
}

read_base_info() {
	if [ ! -x "${LUCKY_BIN}" ]; then
		return 1
	fi
	local baseConfInfo=$(${LUCKY_BIN} -cd ${CONFIG_DIR} -baseConfInfo 2>/dev/null)
	local lucky_port=$(echo "$baseConfInfo" | grep -o '"AdminWebListenPort":[0-9]*' | sed 's/"AdminWebListenPort"://')
	local lucky_safeurl=$(echo "$baseConfInfo" | grep -o '"SafeURL":"[^"]*"' | sed 's/"SafeURL":"\([^"]*\)"/\1/')

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
	if pidof lucky > /dev/null; then
		local command="${LUCKY_BIN} -cd ${CONFIG_DIR}"

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

		if [ "$command" != "${LUCKY_BIN} -cd ${CONFIG_DIR}" ]; then
			echo_date "执行命令: $command"
			eval $command
		fi
		echo_date "✅Lucky 重置成功."
	else
		echo_date "⛔️Lucky 进程未运行，请启动后再试."
	fi
	dbus set lucky_reset_safeurl="0"
	dbus set lucky_reset_user="0"
	dbus set lucky_reset_port="0"
	dbus set lucky_reset_disable="0"
}

# ==================== 方案 B: 安全在线更新核心逻辑 ====================
fetch_latest_ver(){
	local API_URL="https://api.github.com/repos/mizb/MerlinLucky/releases/latest"
	local VER=$(curl -kfsSL --connect-timeout 6 -m 10 "${API_URL}" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
	if [ -z "${VER}" ]; then
		VER=$(curl -kfsSL --connect-timeout 6 -m 10 "https://ghproxy.net/${API_URL}" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
	fi
	echo "${VER}"
}

check_update(){
	echo_date "🔍 正在连接检测最新版本..."
	local LATEST=$(fetch_latest_ver)
	if [ -z "${LATEST}" ]; then
		echo_date "❌ 检查更新失败：网络连接超时或无法解析 GitHub API！"
		return 1
	fi
	local LATEST_NUM="${LATEST#v}"
	local CURRENT_NUM=$(cat /koolshare/lucky/version 2>/dev/null || dbus get lucky_version)
	dbus set lucky_latest_version="${LATEST_NUM}"
	echo_date "✅ 检测完成！本地版本: v${CURRENT_NUM:-未知}，线上最新: v${LATEST_NUM}"
}

update_core(){
	echo_date "🚀 开始执行安全热更新..."
	local ARCH=$(uname -m)
	local CORE_ARCH=""
	case "${ARCH}" in
		aarch64|arm64) CORE_ARCH="arm64" ;;
		armv7l|armv7)  CORE_ARCH="armv7" ;;
		*)
			echo_date "❌ 探测到不受支持的架构: ${ARCH}，拒绝更新！"
			return 1
			;;
	esac
	echo_date "🖥️ 硬件架构校验锁定: ${ARCH} -> 匹配包: ${CORE_ARCH}"

	local LATEST=$(fetch_latest_ver)
	[ -z "${LATEST}" ] && echo_date "❌ 获取最新版本信息失败，更新中止！" && return 1

	local LATEST_NUM="${LATEST#v}"
	local CURRENT_NUM=$(cat /koolshare/lucky/version 2>/dev/null || dbus get lucky_version)
	if [ "${LATEST_NUM}" == "${CURRENT_NUM}" ] && [ "$1" != "force" ]; then
		echo_date "✅ 当前内核已是最新版 (v${CURRENT_NUM})，无需更新。"
		return 0
	fi

	local PKG_NAME="MerlinLucky_${LATEST}_${CORE_ARCH}.tar.gz"
	local DL_URL="https://github.com/mizb/MerlinLucky/releases/download/${LATEST}/${PKG_NAME}"
	local TMP_DIR="/tmp/lucky_update_sandbox"
	rm -rf "${TMP_DIR}" && mkdir -p "${TMP_DIR}"

	echo_date "⬇️ 正在下载纯净轻量 XiaoJV 安装包 (${PKG_NAME})..."
	curl -kfsSL --connect-timeout 8 -m 90 -o "${TMP_DIR}/pkg.tar.gz" "${DL_URL}" || \
	curl -kfsSL --connect-timeout 8 -m 90 -o "${TMP_DIR}/pkg.tar.gz" "https://ghproxy.net/${DL_URL}"

	if [ ! -s "${TMP_DIR}/pkg.tar.gz" ]; then
		echo_date "❌ 安装包下载失败或文件为空！已放弃更新。"
		rm -rf "${TMP_DIR}"
		return 1
	fi

	echo_date "📦 正在解压并进行【沙盒预执行校验】..."
	tar -zxf "${TMP_DIR}/pkg.tar.gz" -C "${TMP_DIR}/"
	local TEST_BIN="${TMP_DIR}/lucky/bin/lucky"
	if [ ! -f "${TEST_BIN}" ]; then
		echo_date "❌ 压缩包内未包含 lucky 执行文件，包体异常！"
		rm -rf "${TMP_DIR}"
		return 1
	fi

	chmod +x "${TEST_BIN}"
	local PROBE_TEST=$("${TEST_BIN}" -info 2>&1 || echo "")
	if ! echo "${PROBE_TEST}" | grep -q '"Version"'; then
		echo_date "❌ 致命错误：新内核在当前路由器无法运行（架构不匹配或下载损坏）！"
		echo_date "🛡️ 熔断机制触发：立即放弃更新，原有系统完好无损！"
		rm -rf "${TMP_DIR}"
		return 1
	fi
	echo_date "🟢 沙盒预执行测试通过！架构完全兼容！"

	# 备份当前内核
	cp -f ${LUCKY_BIN} ${LUCKY_BIN}.bak 2>/dev/null

	echo_date "⏸️ 临时停止当前 Lucky 进程..."
	close_lucky_process

	echo_date "🔄 正在原子替换核心组件与管理脚本..."
	cp -f "${TEST_BIN}" ${LUCKY_BIN}
	chmod +x ${LUCKY_BIN}
	[ -d "${TMP_DIR}/lucky/scripts" ] && cp -rf "${TMP_DIR}/lucky/scripts/"* /koolshare/scripts/ 2>/dev/null
	[ -d "${TMP_DIR}/lucky/webs" ] && cp -rf "${TMP_DIR}/lucky/webs/"* /koolshare/webs/ 2>/dev/null
	chmod +x /koolshare/scripts/lucky*.sh 2>/dev/null

	echo "${LATEST_NUM}" > /koolshare/lucky/version
	dbus set lucky_version="${LATEST_NUM}"
	dbus set lucky_binary="${LATEST_NUM}"
	dbus set softcenter_module_lucky_version="${LATEST_NUM}"

	echo_date "🚀 启动新版本..."
	start_lucky_process

	sleep 2
	if pidof lucky >/dev/null; then
		echo_date "🎉 Lucky 已成功平滑升级至 v${LATEST_NUM}！配置与证书完整保留。"
		rm -rf "${TMP_DIR}" ${LUCKY_BIN}.bak
	else
		echo_date "⚠️ 警告：新内核启动异常！正在自动秒级回滚..."
		cp -f ${LUCKY_BIN}.bak ${LUCKY_BIN}
		start_lucky_process
		echo_date "🛡️ 已回滚至原版本！"
		rm -rf "${TMP_DIR}"
		return 1
	fi
}

manage_autoupdate_cron(){
	if [ "${lucky_autoupdate}" == "1" ]; then
		cru a lucky_auto_update "30 4 * * * /koolshare/scripts/lucky_config.sh auto_update >/dev/null 2>&1"
		echo_date "⏰ 已开启每天凌晨 04:30 自动巡检更新任务"
	else
		cru d lucky_auto_update 2>/dev/null
		echo_date "⏰ 已关闭定时自动巡检更新任务"
	fi
}

close_lucky(){
	rm -rf ${LUCKY_LOG_FILE}
	[ -f "${LOG_FILE}" ] && [ $(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0) -gt 102400 ] && tail -n 200 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
	close_lucky_process
}

start_lucky(){
	[ -f "${LOG_FILE}" ] && [ $(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0) -gt 102400 ] && tail -n 200 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
	close_lucky_process
	read_version
	sleep 1
	read_base_info
	sleep 1
	start_lucky_process
	manage_autoupdate_cron
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
		${LUCKY_BIN} -cd ${CONFIG_DIR} -rRestart
	fi
	;;	
stop)
	close_lucky
	;;
auto_update)
	update_core >> /tmp/upload/lucky_autoupdate.log 2>&1
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
	manage_autoupdate_cron | tee -a ${LOG_FILE}
	echo DD01N05S | tee -a ${LOG_FILE}
	unset_lock
	;;
check_update)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	check_update | tee -a ${LOG_FILE}
	echo DD01N05S | tee -a ${LOG_FILE}
	unset_lock
	;;
update_core)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	update_core "force" | tee -a ${LOG_FILE}
	echo DD01N05S | tee -a ${LOG_FILE}
	unset_lock
	;;
status)
	check_status
	;;
esac
