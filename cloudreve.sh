#!/usr/bin/env bash
#
# Cloudreve 一键启动管理脚本
# 支持后台运行和进程监控
#

sh_ver="1.0.0-南栀（请勿去除版权信息）"
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
Info="[${Green_font_prefix}信息${Font_color_suffix}]"
Error="[${Red_font_prefix}错误${Font_color_suffix}]"
Tip="[${Green_font_prefix}注意${Font_color_suffix}]"

# 配置变量
WORK_DIR=$(pwd)
CLOUDREVE_PATH="${WORK_DIR}/cloudreve"
LICENSE_KEY=""
LICENSE_KEY_FILE="${WORK_DIR}/cloudreve_license.conf"
VERSION_TYPE_FILE="${WORK_DIR}/cloudreve_version.conf"
VERSION_TYPE=""
PID_FILE="/var/run/cloudreve.pid"
LOG_FILE="${WORK_DIR}/cloudreve.log"

check_root() {
    [[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限。" && exit 1
}

read_license_key() {
    if [[ -f "${LICENSE_KEY_FILE}" ]]; then
        LICENSE_KEY=$(cat "${LICENSE_KEY_FILE}")
        if [[ -n ${LICENSE_KEY} ]]; then
            return 0
        fi
    fi
    return 1
}

save_license_key() {
    echo "${LICENSE_KEY}" > "${LICENSE_KEY_FILE}"
    chmod 600 "${LICENSE_KEY_FILE}"
}

input_license_key() {
    echo -e "${Info} 请输入 Cloudreve License Key："
    echo -e "${Tip} License Key 通常是一串长字符串"
    echo ""
    read -e -p "License Key: " input_key
    
    if [[ -z ${input_key} ]]; then
        echo -e "${Error} License Key 不能为空！"
        return 1
    fi
    
    LICENSE_KEY=${input_key}
    
    echo ""
    read -e -p "是否保存 License Key 到配置文件？（下次启动无需重新输入）[Y/n]: " save_confirm
    [[ -z "${save_confirm}" ]] && save_confirm="y"
    
    if [[ ${save_confirm} == [Yy] ]]; then
        save_license_key
        echo -e "${Info} License Key 已保存到: ${LICENSE_KEY_FILE}"
    else
        echo -e "${Tip} License Key 未保存，下次启动需要重新输入"
    fi
    
    return 0
}

check_license_key() {
    if ! read_license_key; then
        echo -e "${Tip} 未找到已保存的 License Key"
        if ! input_license_key; then
            return 1
        fi
    else
        echo -e "${Info} 已加载保存的 License Key"
    fi
}

check_cloudreve_exists() {
    if [[ ! -f "${CLOUDREVE_PATH}" ]]; then
        echo -e "${Error} Cloudreve 可执行文件不存在: ${CLOUDREVE_PATH}"
        echo -e "${Tip} 请确保 cloudreve 文件在当前目录"
        exit 1
    fi
    
    # 社区版需要确保有执行权限
    if [[ ! -x "${CLOUDREVE_PATH}" ]]; then
        echo -e "${Info} 添加执行权限..."
        chmod +x "${CLOUDREVE_PATH}"
    fi
}

read_version_type() {
    if [[ -f "${VERSION_TYPE_FILE}" ]]; then
        VERSION_TYPE=$(cat "${VERSION_TYPE_FILE}" | tr '[:upper:]' '[:lower:]')
        if [[ "${VERSION_TYPE}" == "pro" ]] || [[ "${VERSION_TYPE}" == "community" ]]; then
            return 0
        fi
    fi
    return 1
}

save_version_type() {
    echo "${VERSION_TYPE}" > "${VERSION_TYPE_FILE}"
    chmod 600 "${VERSION_TYPE_FILE}"
}

select_version_type() {
    echo -e "${Info} 请选择 Cloudreve 版本："
    echo -e "  ${Green_font_prefix}1.${Font_color_suffix} Pro 版（需要 License Key）"
    echo -e "  ${Green_font_prefix}2.${Font_color_suffix} 社区版（无需 License Key）"
    echo ""
    read -e -p "请输入选项 [1-2]: " version_choice
    
    case "${version_choice}" in
    1)
        VERSION_TYPE="pro"
        ;;
    2)
        VERSION_TYPE="community"
        ;;
    *)
        echo -e "${Error} 无效的选项！"
        return 1
        ;;
    esac
    
    echo ""
    read -e -p "是否保存版本选择到配置文件？（下次启动无需重新选择）[Y/n]: " save_confirm
    [[ -z "${save_confirm}" ]] && save_confirm="y"
    
    if [[ ${save_confirm} == [Yy] ]]; then
        save_version_type
        echo -e "${Info} 版本选择已保存到: ${VERSION_TYPE_FILE}"
    else
        echo -e "${Tip} 版本选择未保存，下次启动需要重新选择"
    fi
    
    return 0
}

check_version_type() {
    if ! read_version_type; then
        echo -e "${Tip} 未找到已保存的版本选择"
        if ! select_version_type; then
            return 1
        fi
    else
        echo -e "${Info} 已加载保存的版本选择: ${Green_font_prefix}${VERSION_TYPE}${Font_color_suffix}"
    fi
    return 0
}

check_pid() {
    if [[ -f ${PID_FILE} ]]; then
        PID=$(cat ${PID_FILE})
        if [[ -n ${PID} ]] && kill -0 ${PID} 2>/dev/null; then
            return 0
        else
            rm -f ${PID_FILE}
            return 1
        fi
    else
        # 只查找 cloudreve 可执行文件，排除 .sh 脚本
        PID=$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | awk '{print $2}' | head -n 1)
        if [[ -n ${PID} ]]; then
            echo ${PID} > ${PID_FILE}
            return 0
        fi
        return 1
    fi
}

check_systemd_service() {
    if systemctl is-active --quiet cloudreve 2>/dev/null; then
        return 0
    fi
    return 1
}

start_cloudreve() {
    check_cloudreve_exists
    
    # 检查并选择版本类型
    if ! check_version_type; then
        return 1
    fi
    
    # Pro版需要License Key
    if [[ "${VERSION_TYPE}" == "pro" ]]; then
        if ! check_license_key; then
            return 1
        fi
    fi
    
    # 检查是否有进程在运行
    if check_pid; then
        echo -e "${Error} Cloudreve 已经在运行中！PID: ${PID}"
        return 1
    fi
    
    # 检查是否有 systemd 服务在运行
    if check_systemd_service; then
        echo -e "${Error} Cloudreve systemd 服务正在运行中！"
        echo -e "${Tip} 请先停止 systemd 服务: systemctl stop cloudreve"
        return 1
    fi
    
    echo -e "${Info} 启动 Cloudreve (${VERSION_TYPE}版)..."
    
    # 社区版确保有执行权限
    if [[ "${VERSION_TYPE}" == "community" ]]; then
        chmod +x "${CLOUDREVE_PATH}"
    fi
    
    # 后台运行 Cloudreve，使用 setsid 确保完全脱离终端
    cd "${WORK_DIR}"
    if [[ "${VERSION_TYPE}" == "pro" ]]; then
        nohup setsid ${CLOUDREVE_PATH} --license-key "${LICENSE_KEY}" >> ${LOG_FILE} 2>&1 &
    else
        nohup setsid ${CLOUDREVE_PATH} >> ${LOG_FILE} 2>&1 &
    fi
    
    # 保存 PID
    NEW_PID=$!
    echo ${NEW_PID} > ${PID_FILE}
    
    # 使用 disown 确保进程完全脱离 shell
    disown ${NEW_PID} 2>/dev/null || true
    
    sleep 2
    
    if check_pid; then
        echo -e "${Info} Cloudreve 启动成功！PID: ${PID}"
        echo -e "${Info} 日志文件: ${LOG_FILE}"
        show_status
    else
        echo -e "${Error} Cloudreve 启动失败！"
        echo -e "${Tip} 查看日志: tail -f ${LOG_FILE}"
        return 1
    fi
}

stop_cloudreve() {
    # 检查是否有进程在运行
    has_process=false
    if check_pid; then
        has_process=true
    fi
    
    # 检查是否有 systemd 服务在运行
    has_systemd=false
    if check_systemd_service; then
        has_systemd=true
    fi
    
    if [[ ${has_process} == false ]] && [[ ${has_systemd} == false ]]; then
        echo -e "${Error} Cloudreve 没有运行！"
        return 1
    fi
    
    echo -e "${Info} 停止 Cloudreve..."
    
    # 如果 systemd 服务在运行，先停止服务
    if [[ ${has_systemd} == true ]]; then
        echo -e "${Info} 检测到 systemd 服务正在运行，正在停止..."
        systemctl stop cloudreve 2>/dev/null
        sleep 2
    fi
    
    # 查找所有 cloudreve 进程（排除脚本）
    all_pids=$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | awk '{print $2}')
    
    if [[ -n ${all_pids} ]]; then
        echo -e "${Info} 发现以下 Cloudreve 进程:"
        ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh
        echo ""
        
        echo -e "${Info} 强制停止所有 Cloudreve 进程..."
        
        # 逐个停止进程
        for pid in ${all_pids}; do
            kill -9 ${pid} 2>/dev/null
            echo -e "${Info} 已停止进程: ${pid}"
        done
        
        # 清理 PID 文件
        rm -f ${PID_FILE}
        
        sleep 1
        
        # 验证是否成功
        remaining=$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | awk '{print $2}')
        if [[ -z ${remaining} ]]; then
            echo -e "${Info} 所有 Cloudreve 进程已停止！"
        else
            echo -e "${Error} 仍有进程未停止: ${remaining}"
            echo -e "${Tip} 请手动执行: kill -9 ${remaining}"
        fi
    else
        echo -e "${Info} 没有发现 Cloudreve 进程"
        rm -f ${PID_FILE}
    fi
    
    echo -e "${Info} Cloudreve 已停止！"
}

restart_cloudreve() {
    echo -e "${Info} 重启 Cloudreve..."
    
    # 检查是否有进程在运行
    has_process=false
    if check_pid; then
        has_process=true
    fi
    
    # 检查是否有 systemd 服务在运行
    has_systemd=false
    if check_systemd_service; then
        has_systemd=true
    fi
    
    if [[ ${has_process} == true ]] || [[ ${has_systemd} == true ]]; then
        stop_cloudreve
    fi
    
    sleep 2
    start_cloudreve
}

force_stop_all() {
    echo -e "${Info} 查找所有 Cloudreve 进程..."
    
    # 检查是否有 systemd 服务在运行
    has_systemd=false
    if check_systemd_service; then
        has_systemd=true
    fi
    
    # 只查找 cloudreve 可执行文件，排除 .sh 脚本
    all_pids=$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | awk '{print $2}')
    
    if [[ -z ${all_pids} ]] && [[ ${has_systemd} == false ]]; then
        echo -e "${Info} 没有发现 Cloudreve 进程"
        return
    fi
    
    if [[ -n ${all_pids} ]]; then
        echo -e "${Info} 发现以下 Cloudreve 进程:"
        ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh
        echo ""
    fi
    
    if [[ ${has_systemd} == true ]]; then
        echo -e "${Info} 检测到 systemd 服务正在运行"
        echo ""
    fi
    
    read -e -p "确认强制停止所有 Cloudreve 进程？[y/N]: " confirm
    
    if [[ ${confirm} != [Yy] ]]; then
        echo -e "${Info} 已取消"
        return
    fi
    
    echo -e "${Info} 强制停止所有 Cloudreve 进程..."
    
    # 如果 systemd 服务在运行，先停止服务
    if [[ ${has_systemd} == true ]]; then
        echo -e "${Info} 正在停止 systemd 服务..."
        systemctl stop cloudreve 2>/dev/null
        sleep 2
    fi
    
    # 逐个停止进程
    if [[ -n ${all_pids} ]]; then
        for pid in ${all_pids}; do
            kill -9 ${pid} 2>/dev/null
            echo -e "${Info} 已停止进程: ${pid}"
        done
    fi
    
    # 清理 PID 文件
    rm -f ${PID_FILE}
    
    sleep 1
    
    # 验证是否成功
    remaining=$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | awk '{print $2}')
    if [[ -z ${remaining} ]]; then
        echo -e "${Info} 所有 Cloudreve 进程已停止！"
    else
        echo -e "${Error} 仍有进程未停止: ${remaining}"
        echo -e "${Tip} 请手动执行: kill -9 ${remaining}"
    fi
}

show_status() {
    # 显示版本类型
    if read_version_type; then
        if [[ "${VERSION_TYPE}" == "pro" ]]; then
            echo -e "${Info} 版本类型: ${Green_font_prefix}Pro 版${Font_color_suffix}"
        else
            echo -e "${Info} 版本类型: ${Green_font_prefix}社区版${Font_color_suffix}"
        fi
    else
        echo -e "${Info} 版本类型: ${Red_font_prefix}未选择${Font_color_suffix}"
    fi
    
    if check_pid; then
        echo -e "${Info} Cloudreve 运行状态: ${Green_font_prefix}运行中${Font_color_suffix}"
        echo -e "${Info} PID: ${Green_font_prefix}${PID}${Font_color_suffix}"
        echo -e "${Info} 工作目录: ${Green_font_prefix}${WORK_DIR}${Font_color_suffix}"
        echo -e "${Info} 日志文件: ${Green_font_prefix}${LOG_FILE}${Font_color_suffix}"
        
        # 显示内存使用
        if command -v ps >/dev/null 2>&1; then
            MEM=$(ps -p ${PID} -o rss= 2>/dev/null | awk '{printf "%.2f MB", $1/1024}')
            [[ -n ${MEM} ]] && echo -e "${Info} 内存使用: ${Green_font_prefix}${MEM}${Font_color_suffix}"
        fi
        
        # 显示运行时长
        if command -v ps >/dev/null 2>&1; then
            UPTIME=$(ps -p ${PID} -o etime= 2>/dev/null | sed 's/^[[:space:]]*//')
            [[ -n ${UPTIME} ]] && echo -e "${Info} 运行时长: ${Green_font_prefix}${UPTIME}${Font_color_suffix}"
        fi
    else
        echo -e "${Info} Cloudreve 运行状态: ${Red_font_prefix}未运行${Font_color_suffix}"
    fi
}

view_log() {
    if [[ ! -f ${LOG_FILE} ]]; then
        echo -e "${Error} 日志文件不存在！"
        return 1
    fi
    
    echo -e "${Info} 实时查看日志（按 Ctrl+C 退出）..."
    echo ""
    tail -f ${LOG_FILE}
}

clear_log() {
    if [[ ! -f ${LOG_FILE} ]]; then
        echo -e "${Error} 日志文件不存在！"
        return 1
    fi
    
    read -e -p "确认清空日志？[y/N]: " confirm
    if [[ ${confirm} == [Yy] ]]; then
        > ${LOG_FILE}
        echo -e "${Info} 日志已清空！"
    else
        echo -e "${Info} 已取消"
    fi
}

install_service() {
    check_root
    check_cloudreve_exists
    
    # 检查并选择版本类型
    if ! check_version_type; then
        return 1
    fi
    
    # Pro版需要License Key
    if [[ "${VERSION_TYPE}" == "pro" ]]; then
        if ! check_license_key; then
            return 1
        fi
    fi
    
    echo -e "${Info} 创建 systemd 服务..."
    
    # 根据版本类型构建启动命令
    if [[ "${VERSION_TYPE}" == "pro" ]]; then
        EXEC_START="${WORK_DIR}/cloudreve --license-key \"${LICENSE_KEY}\""
    else
        EXEC_START="${WORK_DIR}/cloudreve"
    fi
    
    cat > /etc/systemd/system/cloudreve.service <<EOF
[Unit]
Description=Cloudreve File Manager
Documentation=https://docs.cloudreve.org
After=network.target

[Service]
Type=simple
WorkingDirectory=${WORK_DIR}
ExecStart=${EXEC_START}
Restart=always
RestartSec=3
StandardOutput=append:${WORK_DIR}/cloudreve.log
StandardError=append:${WORK_DIR}/cloudreve.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable cloudreve
    
    echo -e "${Info} systemd 服务已创建！"
    echo -e "${Tip} 使用以下命令管理："
    echo -e "  启动: ${Green_font_prefix}systemctl start cloudreve${Font_color_suffix}"
    echo -e "  停止: ${Green_font_prefix}systemctl stop cloudreve${Font_color_suffix}"
    echo -e "  重启: ${Green_font_prefix}systemctl restart cloudreve${Font_color_suffix}"
    echo -e "  状态: ${Green_font_prefix}systemctl status cloudreve${Font_color_suffix}"
    echo -e "  日志: ${Green_font_prefix}journalctl -u cloudreve -f${Font_color_suffix}"
}

remove_service() {
    check_root
    
    if [[ ! -f /etc/systemd/system/cloudreve.service ]]; then
        echo -e "${Error} systemd 服务不存在！"
        return 1
    fi
    
    echo -e "${Info} 停止并删除 systemd 服务..."
    
    systemctl stop cloudreve 2>/dev/null
    systemctl disable cloudreve 2>/dev/null
    rm -f /etc/systemd/system/cloudreve.service
    systemctl daemon-reload
    
    echo -e "${Info} systemd 服务已删除！"
}

monitor_cloudreve() {
    echo -e "${Info} 开始监控 Cloudreve 进程..."
    echo -e "${Tip} 按 Ctrl+C 停止监控"
    echo ""
    
    while true; do
        if check_pid; then
            echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${Green_font_prefix}✓${Font_color_suffix} Cloudreve 运行中 (PID: ${PID})"
        else
            echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${Red_font_prefix}✗${Font_color_suffix} Cloudreve 已停止，正在重启..."
            start_cloudreve
        fi
        sleep 10
    done
}

change_license_key() {
    # 检查版本类型
    if ! read_version_type; then
        echo -e "${Error} 请先选择版本类型！"
        return 1
    fi
    
    if [[ "${VERSION_TYPE}" != "pro" ]]; then
        echo -e "${Error} 只有 Pro 版需要 License Key！"
        return 1
    fi
    
    echo -e "${Info} 修改 License Key"
    echo ""
    
    if read_license_key; then
        echo -e "${Info} 当前已保存的 License Key: ${Green_font_prefix}${LICENSE_KEY:0:20}...${Font_color_suffix}"
        echo ""
    fi
    
    if input_license_key; then
        echo -e "${Info} License Key 已更新！"
        
        # 如果 Cloudreve 正在运行，提示重启
        if check_pid; then
            echo ""
            read -e -p "Cloudreve 正在运行，是否立即重启以应用新的 License Key？[Y/n]: " restart_confirm
            [[ -z "${restart_confirm}" ]] && restart_confirm="y"
            
            if [[ ${restart_confirm} == [Yy] ]]; then
                restart_cloudreve
            else
                echo -e "${Tip} 请手动重启 Cloudreve 以应用新的 License Key"
            fi
        fi
    fi
}

view_license_key() {
    # 检查版本类型
    if read_version_type; then
        if [[ "${VERSION_TYPE}" != "pro" ]]; then
            echo -e "${Info} 当前版本: ${Green_font_prefix}社区版${Font_color_suffix}"
            echo -e "${Tip} 社区版不需要 License Key"
            return 0
        fi
    fi
    
    if read_license_key; then
        echo -e "${Info} 当前保存的 License Key:"
        echo -e "${Green_font_prefix}${LICENSE_KEY}${Font_color_suffix}"
        echo ""
        echo -e "${Info} 配置文件位置: ${LICENSE_KEY_FILE}"
    else
        echo -e "${Error} 未找到已保存的 License Key"
        echo -e "${Tip} 请先启动 Cloudreve 并输入 License Key"
    fi
}

delete_license_key() {
    if [[ -f "${LICENSE_KEY_FILE}" ]]; then
        read -e -p "确认删除已保存的 License Key？[y/N]: " del_confirm
        if [[ ${del_confirm} == [Yy] ]]; then
            rm -f "${LICENSE_KEY_FILE}"
            echo -e "${Info} License Key 已删除"
            echo -e "${Tip} 下次启动需要重新输入"
        else
            echo -e "${Info} 已取消"
        fi
    else
        echo -e "${Error} 没有已保存的 License Key"
    fi
}

auto_restart_daemon() {
    # 检查并选择版本类型
    if ! check_version_type; then
        return 1
    fi
    
    # Pro版需要License Key
    if [[ "${VERSION_TYPE}" == "pro" ]]; then
        if ! check_license_key; then
            return 1
        fi
    fi
    
    echo -e "${Info} 创建自动重启守护进程..."
    
    # 创建监控脚本
    cat > /usr/local/bin/cloudreve-monitor.sh <<EOF
#!/bin/bash
CLOUDREVE_PATH="${WORK_DIR}/cloudreve"
VERSION_TYPE_FILE="${VERSION_TYPE_FILE}"
LICENSE_KEY_FILE="${LICENSE_KEY_FILE}"
LOG_FILE="${WORK_DIR}/cloudreve.log"
PID_FILE="/var/run/cloudreve.pid"

# 读取版本类型
if [[ -f "\${VERSION_TYPE_FILE}" ]]; then
    VERSION_TYPE=\$(cat "\${VERSION_TYPE_FILE}" | tr '[:upper:]' '[:lower:]')
    if [[ "\${VERSION_TYPE}" != "pro" ]] && [[ "\${VERSION_TYPE}" != "community" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: 版本类型文件内容无效，应为 'pro' 或 'community'，文件路径: \${VERSION_TYPE_FILE}" >> \${LOG_FILE}
        exit 1
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: 找不到版本类型文件，文件路径: \${VERSION_TYPE_FILE}" >> \${LOG_FILE}
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 提示: 请先运行主脚本选择版本类型，或手动创建该文件并写入 'pro' 或 'community'" >> \${LOG_FILE}
    exit 1
fi

# Pro版需要读取 License Key
if [[ "\${VERSION_TYPE}" == "pro" ]]; then
    if [[ -f "\${LICENSE_KEY_FILE}" ]]; then
        LICENSE_KEY=\$(cat "\${LICENSE_KEY_FILE}")
        if [[ -z "\${LICENSE_KEY}" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: License Key 文件为空，文件路径: \${LICENSE_KEY_FILE}" >> \${LOG_FILE}
            exit 1
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: 找不到 License Key 文件，文件路径: \${LICENSE_KEY_FILE}" >> \${LOG_FILE}
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 提示: Pro 版需要 License Key，请先运行主脚本配置 License Key" >> \${LOG_FILE}
        exit 1
    fi
fi

while true; do
    if [[ -f \${PID_FILE} ]]; then
        PID=\$(cat \${PID_FILE})
        if ! kill -0 \${PID} 2>/dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cloudreve 进程已停止，正在重启..." >> \${LOG_FILE}
            cd "${WORK_DIR}"
            chmod +x \${CLOUDREVE_PATH}
            if [[ "\${VERSION_TYPE}" == "pro" ]]; then
                nohup setsid \${CLOUDREVE_PATH} --license-key "\${LICENSE_KEY}" >> \${LOG_FILE} 2>&1 &
            else
                nohup setsid \${CLOUDREVE_PATH} >> \${LOG_FILE} 2>&1 &
            fi
            NEW_PID=\$!
            echo \${NEW_PID} > \${PID_FILE}
            disown \${NEW_PID} 2>/dev/null || true
        fi
    else
        PID=\$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | awk '{print \$2}' | head -n 1)
        if [[ -z \${PID} ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cloudreve 未运行，正在启动..." >> \${LOG_FILE}
            cd "${WORK_DIR}"
            chmod +x \${CLOUDREVE_PATH}
            if [[ "\${VERSION_TYPE}" == "pro" ]]; then
                nohup setsid \${CLOUDREVE_PATH} --license-key "\${LICENSE_KEY}" >> \${LOG_FILE} 2>&1 &
            else
                nohup setsid \${CLOUDREVE_PATH} >> \${LOG_FILE} 2>&1 &
            fi
            NEW_PID=\$!
            echo \${NEW_PID} > \${PID_FILE}
            disown \${NEW_PID} 2>/dev/null || true
        else
            echo \${PID} > \${PID_FILE}
        fi
    fi
    sleep 30
done
EOF
    
    chmod +x /usr/local/bin/cloudreve-monitor.sh
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/cloudreve-monitor.service <<EOF
[Unit]
Description=Cloudreve Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudreve-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable cloudreve-monitor
    systemctl start cloudreve-monitor
    
    echo -e "${Info} 自动重启守护进程已启动！"
    echo -e "${Tip} 守护进程每 30 秒检查一次 Cloudreve 状态"
    echo -e "${Tip} 停止守护: ${Green_font_prefix}systemctl stop cloudreve-monitor${Font_color_suffix}"
    echo -e "${Tip} 禁用守护: ${Green_font_prefix}systemctl disable cloudreve-monitor${Font_color_suffix}"
}

ask_continue() {
    echo ""
    read -e -p "是否继续？[Y/n]: " continue_confirm
    [[ -z "${continue_confirm}" ]] && continue_confirm="y"
    
    if [[ ${continue_confirm} == [Yy] ]]; then
        return 0
    else
        exit 0
    fi
}

show_menu() {
    clear
    echo -e "
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Cloudreve 启动管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${Green_font_prefix}1.${Font_color_suffix} 启动 Cloudreve
  ${Green_font_prefix}2.${Font_color_suffix} 停止 Cloudreve
  ${Green_font_prefix}3.${Font_color_suffix} 重启 Cloudreve
  ${Green_font_prefix}4.${Font_color_suffix} 查看状态
  ————————————————————————
  ${Green_font_prefix}5.${Font_color_suffix} 查看日志（实时）
  ${Green_font_prefix}6.${Font_color_suffix} 清空日志
  ————————————————————————
  ${Green_font_prefix}7.${Font_color_suffix} 监控进程（手动）
  ${Green_font_prefix}8.${Font_color_suffix} 启用自动重启守护
  ————————————————————————
  ${Green_font_prefix}9.${Font_color_suffix} 安装 systemd 服务
  ${Green_font_prefix}10.${Font_color_suffix} 删除 systemd 服务
  ————————————————————————
  ${Green_font_prefix}11.${Font_color_suffix} 查看 License Key
  ${Green_font_prefix}12.${Font_color_suffix} 修改 License Key
  ${Green_font_prefix}13.${Font_color_suffix} 删除 License Key
  ————————————————————————
  ${Red_font_prefix}14.${Font_color_suffix} 强制停止所有进程
  ${Green_font_prefix}0.${Font_color_suffix} 退出脚本
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if check_pid; then
        echo -e "  当前状态: ${Green_font_prefix}运行中${Font_color_suffix} (PID: ${PID})"
    else
        echo -e "  当前状态: ${Red_font_prefix}未运行${Font_color_suffix}"
    fi
    
    # 显示所有 Cloudreve 进程数量（排除脚本）
    all_count=$(ps aux | grep -E '[^a-z]cloudreve[^\.sh]' | grep -v grep | grep -v cloudreve.sh | wc -l)
    if [[ ${all_count} -gt 0 ]]; then
        echo -e "  检测到 Cloudreve 进程数: ${Red_font_prefix}${all_count}${Font_color_suffix}"
    fi
    
    # 显示版本类型
    if read_version_type; then
        if [[ "${VERSION_TYPE}" == "pro" ]]; then
            echo -e "  版本类型: ${Green_font_prefix}Pro 版${Font_color_suffix}"
        else
            echo -e "  版本类型: ${Green_font_prefix}社区版${Font_color_suffix}"
        fi
    else
        echo -e "  版本类型: ${Red_font_prefix}未选择${Font_color_suffix}"
    fi
    
    # 显示 systemd 服务状态
    if check_systemd_service; then
        echo -e "  systemd 服务: ${Green_font_prefix}运行中${Font_color_suffix}"
    fi
    
    # 显示 License Key 状态（仅Pro版显示）
    if read_version_type && [[ "${VERSION_TYPE}" == "pro" ]]; then
        if [[ -f "${LICENSE_KEY_FILE}" ]]; then
            echo -e "  License Key: ${Green_font_prefix}已保存${Font_color_suffix}"
        else
            echo -e "  License Key: ${Red_font_prefix}未保存${Font_color_suffix}"
        fi
    fi
    
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    read -e -p " 请输入数字 [0-14]: " num
    case "$num" in
    1)
        start_cloudreve
        ask_continue
        show_menu
        ;;
    2)
        stop_cloudreve
        ask_continue
        show_menu
        ;;
    3)
        restart_cloudreve
        ask_continue
        show_menu
        ;;
    4)
        show_status
        ask_continue
        show_menu
        ;;
    5)
        view_log
        ask_continue
        show_menu
        ;;
    6)
        clear_log
        ask_continue
        show_menu
        ;;
    7)
        monitor_cloudreve
        ask_continue
        show_menu
        ;;
    8)
        check_root
        auto_restart_daemon
        ask_continue
        show_menu
        ;;
    9)
        install_service
        ask_continue
        show_menu
        ;;
    10)
        remove_service
        ask_continue
        show_menu
        ;;
    11)
        view_license_key
        ask_continue
        show_menu
        ;;
    12)
        change_license_key
        ask_continue
        show_menu
        ;;
    13)
        delete_license_key
        ask_continue
        show_menu
        ;;
    14)
        force_stop_all
        ask_continue
        show_menu
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${Error} 请输入正确的数字 [0-14]"
        sleep 2
        show_menu
        ;;
    esac
}

# 如果有参数，直接执行对应功能
if [[ $# -gt 0 ]]; then
    case "$1" in
    start)
        start_cloudreve
        ;;
    stop)
        stop_cloudreve
        ;;
    restart)
        restart_cloudreve
        ;;
    status)
        show_status
        ;;
    log)
        view_log
        ;;
    monitor)
        monitor_cloudreve
        ;;
    force-stop|forcestop)
        force_stop_all
        ;;
    *)
        echo -e "${Error} 未知参数: $1"
        echo -e "${Info} 可用参数: start|stop|restart|status|log|monitor|force-stop"
        exit 1
        ;;
    esac
else
    # 无参数，显示菜单
    show_menu
fi

