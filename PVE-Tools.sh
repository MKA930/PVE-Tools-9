#!/bin/bash

# PVE 9.0 配置工具脚本
# 功能: 换源、删除订阅弹窗、硬盘管理、系统更新、信息查看等
# 适用于 Proxmox VE 9.0 (基于 Debian 13)

set -euo pipefail

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
NC='\033[0m'

# 全局变量
LOG_FILE="/var/log/pve-tools.log"
DRY_RUN=false

# 日志函数（屏幕彩色，日志纯文本）
log() {
    local level="$1"; local color="$2"; shift 2
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "${color}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}
log_info()    { log INFO "$GREEN" "$@"; }
log_warn()    { log WARN "$YELLOW" "$@"; }
log_error()   { log ERROR "$RED" "$@"; }
log_step()    { log STEP "$CYAN" "$@"; }
log_success() { log SUCCESS "$GREEN" "$@"; }

# 执行命令（支持 dry-run）
run_cmd() {
    if $DRY_RUN; then
        log_info "[DRY-RUN] $*"
    else
        eval "$@"
    fi
}

# 横幅
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗     █████╗ 
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔══██╗
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     ███████╗    ╚██████║
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     ╚════██║     ╚═══██║
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗███████║     █████╔╝
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝     ╚════╝ 
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}                     PVE 9.0 一键配置神器 ${NC}"
    echo -e "${GREEN}                      让 PVE 配置变得简单快乐${NC}"
    echo -e "${CYAN}                        感谢您的使用 ${NC}"
    echo
}

# 权限检查
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "需要 root 权限才能运行"
        echo -e "${YELLOW}请使用: ${CYAN}sudo $0${NC}"
        exit 1
    fi
    touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
}

# 检查 PVE
check_pve_version() {
    if ! command -v pveversion &>/dev/null; then
        log_error "未检测到 PVE 环境"
        exit 1
    fi
    local v=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "检测到 PVE 版本: $v"
}

# 确认操作（双重确认）
confirm_action() {
    local msg="$1"
    echo -e "${YELLOW}$msg${NC}"
    read -rp "输入 'yes' 确认继续: " reply
    [[ "$reply" != "yes" ]] && return 1
    read -rp "再次输入 'CONFIRM' 以最终确认: " confirm
    [[ "$confirm" == "CONFIRM" ]]
}

# 备份文件
backup_file() {
    local file="$1"
    [[ ! -f "$file" ]] && { log_warn "文件不存在: $file"; return 0; }
    local bak="${file}.bak.$(date +%Y%m%d_%H%M%S)"
    run_cmd "cp '$file' '$bak'"
    log_info "已备份 $file -> $bak"
}

# 换源
change_sources() {
    log_step "换源中..."
    backup_file "/etc/apt/sources.list.d/debian.sources"
    cat > /etc/apt/sources.list.d/debian.sources <<'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/pve-enterprise.sources"
        sed -i -E 's/^(Types|URIs|Suites|Components|Signed-By)/#\1/' /etc/apt/sources.list.d/pve-enterprise.sources
    fi
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    log_success "换源完成"
}

# 删除订阅弹窗
remove_subscription_popup() {
    log_step "移除订阅弹窗..."
    local js="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    [[ ! -f "$js" ]] && { log_warn "未找到目标文件"; return 0; }
    backup_file "$js"
    run_cmd "sed -Ezi 's/(Ext.Msg.show\\({\\s+title: gettext\\('No valid sub)/void({ \\/\\/\\1/' '$js'"
    run_cmd "systemctl restart pveproxy.service || true"
    log_success "已移除订阅弹窗"
}

# 合并 local-lvm
merge_local_storage() {
    log_step "合并 local 与 local-lvm..."
    if ! lvdisplay /dev/pve/data &>/dev/null; then
        log_warn "未检测到 local-lvm"
        return 0
    fi
    confirm_action "此操作会删除 local-lvm！不可逆！" || return 1
    run_cmd "lvremove -f /dev/pve/data"
    run_cmd "lvextend -l +100%FREE /dev/pve/root"
    run_cmd "resize2fs /dev/pve/root"
    log_success "local-lvm 已合并到 local"
}

# 删除 swap
remove_swap() {
    log_step "删除 swap..."
    if ! lvdisplay /dev/pve/swap &>/dev/null; then
        log_warn "未检测到 swap"
        return 0
    fi
    confirm_action "此操作会删除 swap！" || return 1
    run_cmd "swapoff /dev/mapper/pve-swap || true"
    backup_file "/etc/fstab"
    sed -i 's|^/dev/pve/swap|# /dev/pve/swap|g' /etc/fstab
    run_cmd "lvremove -f /dev/pve/swap"
    run_cmd "lvextend -l +100%FREE /dev/mapper/pve-root"
    run_cmd "resize2fs /dev/mapper/pve-root"
    log_success "swap 已删除并扩展至 root"
}

# 更新系统
update_system() {
    log_step "更新系统..."
    run_cmd "apt update"
    run_cmd "apt full-upgrade -y"
    run_cmd "apt autoremove -y"
    log_success "系统已更新"
}

# 系统信息
show_system_info() {
    log_step "系统信息:"
    echo -e " PVE: $(pveversion | head -n1)"
    echo -e " 内核: $(uname -r)"
    echo -e " 负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo -e " 内存: $(free -h | awk '/Mem/ {printf \"%s/%s (%d%%)\", $3,$2,$3/$2*100}')"
    df -h | awk '/^\/dev/ {print " "$1" "$3"/"$2" "$5}'
}

# 健康检查
check_system_health() {
    log_step "健康检查..."
    local usage=$(df / | awk 'END{print $5}' | tr -d %)
    (( usage > 90 )) && log_warn "根分区使用率过高: $usage%" || log_info "根分区使用率: $usage%"
}

# 一键配置
quick_setup() {
    change_sources && remove_subscription_popup && update_system
    log_success "一键配置完成"
}

# 菜单
show_menu() {
    echo -e "${MAGENTA}请选择功能：${NC}"
    echo -e "1. 换源"
    echo -e "2. 删除订阅弹窗"
    echo -e "3. 合并 local-lvm"
    echo -e "4. 删除 swap"
    echo -e "5. 更新系统"
    echo -e "6. 显示系统信息"
    echo -e "7. 健康检查"
    echo -e "8. 一键配置"
    echo -e "0. 退出"
    echo
}

# 主程序
main() {
    [[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
    check_root; check_pve_version
    while true; do
        show_banner; show_menu
        read -rp "请输入选择 [0-8]: " choice
        case "$choice" in
            1) change_sources ;;
            2) remove_subscription_popup ;;
            3) merge_local_storage ;;
            4) remove_swap ;;
            5) update_system ;;
            6) show_system_info ;;
            7) check_system_health ;;
            8) quick_setup ;;
            0) log_info "退出"; exit 0 ;;
            *) log_error "无效选择" ;;
        esac
        read -rp "按回车返回菜单..."
    done
}

main "$@"
