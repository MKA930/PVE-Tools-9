#!/bin/bash

# PVE 9.0 配置工具脚本

# 功能: 换源、删除订阅弹窗、硬盘管理、系统更新、信息查看等

# 适用于 Proxmox VE 9.0 (基于 Debian 13)

set -euo pipefail

# 颜色定义

readonly RED=’\033[0;31m’
readonly GREEN=’\033[0;32m’
readonly YELLOW=’\033[1;33m’
readonly BLUE=’\033[0;34m’
readonly CYAN=’\033[0;36m’
readonly MAGENTA=’\033[0;35m’
readonly NC=’\033[0m’

# 全局变量

readonly LOG_FILE=”/var/log/pve-tools.log”
DRY_RUN=false

# 日志函数（屏幕彩色，日志纯文本）

log() {
local level=”$1”
local color=”$2”
shift 2
local msg=”[$(date +’%Y-%m-%d %H:%M:%S’)] [$level] $*”
echo -e “${color}${msg}${NC}”
echo “$msg” >> “$LOG_FILE”
}

log_info()    { log INFO “$GREEN” “$@”; }
log_warn()    { log WARN “$YELLOW” “$@”; }
log_error()   { log ERROR “$RED” “$@”; }
log_step()    { log STEP “$CYAN” “$@”; }
log_success() { log SUCCESS “$GREEN” “$@”; }

# 执行命令（支持 dry-run）

run_cmd() {
if $DRY_RUN; then
log_info “[DRY-RUN] $*”
return 0
else
if ! eval “$@”; then
log_error “命令执行失败: $*”
return 1
fi
fi
}

# 横幅

show_banner() {
clear
echo -e “${BLUE}”
cat << ‘EOF’
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗     █████╗
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔══██╗
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     ███████╗    ╚██████║
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     ╚════██║     ╚═══██║
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗███████║     █████╔╝
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝     ╚════╝
EOF
echo -e “${NC}”
echo -e “${YELLOW}                     PVE 9.0 一键配置神器 ${NC}”
echo -e “${GREEN}                      让 PVE 配置变得简单快乐${NC}”
echo -e “${CYAN}                        感谢您的使用 ${NC}”
echo
}

# 权限检查

check_root() {
if [[ $EUID -ne 0 ]]; then
log_error “需要 root 权限才能运行”
echo -e “${YELLOW}请使用: ${CYAN}sudo $0${NC}”
exit 1
fi

```
# 创建日志文件并设置权限
if ! touch "$LOG_FILE" 2>/dev/null; then
    log_error "无法创建日志文件: $LOG_FILE"
    exit 1
fi
chmod 600 "$LOG_FILE"
```

}

# 检查 PVE 版本

check_pve_version() {
if ! command -v pveversion &>/dev/null; then
log_error “未检测到 PVE 环境”
exit 1
fi

```
local version
if ! version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1 2>/dev/null); then
    log_warn "无法获取PVE版本信息"
    return 1
fi

log_info "检测到 PVE 版本: $version"
```

}

# 确认操作（双重确认）

confirm_action() {
local msg=”$1”
local reply confirm

```
echo -e "${YELLOW}$msg${NC}"
read -rp "输入 'yes' 确认继续: " reply
if [[ "$reply" != "yes" ]]; then
    log_info "用户取消操作"
    return 1
fi

read -rp "再次输入 'CONFIRM' 以最终确认: " confirm
if [[ "$confirm" != "CONFIRM" ]]; then
    log_info "用户取消操作"
    return 1
fi

return 0
```

}

# 备份文件

backup_file() {
local file=”$1”

```
if [[ ! -f "$file" ]]; then
    log_warn "文件不存在: $file"
    return 0
fi

local backup_name="${file}.bak.$(date +%Y%m%d_%H%M%S)"
if run_cmd "cp '$file' '$backup_name'"; then
    log_info "已备份 $file -> $backup_name"
else
    log_error "备份失败: $file"
    return 1
fi
```

}

# 换源

change_sources() {
log_step “开始换源…”

```
# 备份并修改 Debian 源
local debian_sources="/etc/apt/sources.list.d/debian.sources"
backup_file "$debian_sources"

if ! cat > "$debian_sources" <<'EOF'; then
```

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
log_error “写入 Debian 源配置失败”
return 1
fi

```
# 处理企业版源
local enterprise_sources="/etc/apt/sources.list.d/pve-enterprise.sources"
if [[ -f "$enterprise_sources" ]]; then
    backup_file "$enterprise_sources"
    run_cmd "sed -i -E 's/^(Types|URIs|Suites|Components|Signed-By)/#\1/' '$enterprise_sources'"
fi

# 添加无订阅源
local no_sub_sources="/etc/apt/sources.list.d/pve-no-subscription.sources"
if ! cat > "$no_sub_sources" <<'EOF'; then
```

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
log_error “写入 PVE 源配置失败”
return 1
fi

```
log_success "换源完成"
```

}

# 删除订阅弹窗

remove_subscription_popup() {
log_step “移除订阅弹窗…”

```
local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [[ ! -f "$js_file" ]]; then
    log_warn "未找到目标文件: $js_file"
    return 0
fi

backup_file "$js_file"

# 使用更安全的sed命令
if run_cmd "sed -i.bak '/Ext\.Msg\.show.*No valid sub/s/Ext\.Msg\.show/void(/' '$js_file'"; then
    run_cmd "systemctl restart pveproxy.service" || log_warn "重启pveproxy服务失败"
    log_success "已移除订阅弹窗"
else
    log_error "修改JS文件失败"
    return 1
fi
```

}

# 合并 local-lvm 存储

merge_local_storage() {
log_step “准备合并 local 与 local-lvm…”

```
if ! lvdisplay /dev/pve/data &>/dev/null; then
    log_warn "未检测到 local-lvm (data LV)"
    return 0
fi

if ! confirm_action "⚠️ 警告：此操作会删除 local-lvm 存储！所有虚拟机磁盘将丢失！此操作不可逆！"; then
    return 1
fi

log_step "执行合并操作..."
if run_cmd "lvremove -f /dev/pve/data" && \
   run_cmd "lvextend -l +100%FREE /dev/pve/root" && \
   run_cmd "resize2fs /dev/pve/root"; then
    log_success "local-lvm 已成功合并到 local"
else
    log_error "合并操作失败"
    return 1
fi
```

}

# 删除 swap

remove_swap() {
log_step “准备删除 swap…”

```
if ! lvdisplay /dev/pve/swap &>/dev/null; then
    log_warn "未检测到 swap LV"
    return 0
fi

if ! confirm_action "确定要删除 swap 分区吗？"; then
    return 1
fi

log_step "执行删除操作..."
# 关闭swap
run_cmd "swapoff /dev/mapper/pve-swap" || log_warn "关闭swap失败，可能未启用"

# 备份并修改fstab
backup_file "/etc/fstab"
run_cmd "sed -i 's|^/dev/pve/swap|# /dev/pve/swap|g' /etc/fstab"

# 删除LV并扩展root
if run_cmd "lvremove -f /dev/pve/swap" && \
   run_cmd "lvextend -l +100%FREE /dev/mapper/pve-root" && \
   run_cmd "resize2fs /dev/mapper/pve-root"; then
    log_success "swap 已删除并成功扩展 root 分区"
else
    log_error "删除swap操作失败"
    return 1
fi
```

}

# 更新系统

update_system() {
log_step “开始更新系统…”

```
if run_cmd "apt update"; then
    log_info "软件包列表更新完成"
else
    log_error "更新软件包列表失败"
    return 1
fi

if run_cmd "apt full-upgrade -y"; then
    log_info "系统升级完成"
else
    log_error "系统升级失败"
    return 1
fi

run_cmd "apt autoremove -y" || log_warn "清理无用软件包失败"
run_cmd "apt autoclean" || log_warn "清理软件包缓存失败"

log_success "系统更新完成"
```

}

# 显示系统信息

show_system_info() {
log_step “系统信息:”

```
# PVE版本
if command -v pveversion &>/dev/null; then
    echo -e " ${GREEN}PVE版本:${NC} $(pveversion | head -n1)"
fi

# 系统信息
echo -e " ${GREEN}内核版本:${NC} $(uname -r)"
echo -e " ${GREEN}系统负载:${NC}$(uptime | awk -F'load average:' '{print $2}')"

# 内存使用
if command -v free &>/dev/null; then
    echo -e " ${GREEN}内存使用:${NC} $(free -h | awk '/^Mem:/ {printf "%s/%s (%.1f%%)", $3,$2,$3/$2*100}')"
fi

# 磁盘使用
echo -e " ${GREEN}磁盘使用:${NC}"
df -h | awk '/^\/dev/ {printf "   %s %s/%s %s\n", $1, $3, $2, $5}'

# CPU信息
if [[ -f /proc/cpuinfo ]]; then
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^ *//')
    local cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    echo -e " ${GREEN}CPU信息:${NC} $cpu_model (${cpu_cores} 核心)"
fi
```

}

# 健康检查

check_system_health() {
log_step “执行健康检查…”

```
local issues=0

# 检查磁盘使用率
while read -r filesystem usage; do
    local usage_num=${usage%\%}
    if (( usage_num > 90 )); then
        log_warn "磁盘使用率过高: $filesystem $usage"
        ((issues++))
    elif (( usage_num > 80 )); then
        log_info "磁盘使用率偏高: $filesystem $usage"
    fi
done < <(df | awk '/^\/dev/ {print $1, $5}')

# 检查内存使用率
if command -v free &>/dev/null; then
    local mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}')
    if (( mem_usage > 90 )); then
        log_warn "内存使用率过高: ${mem_usage}%"
        ((issues++))
    fi
fi

# 检查系统负载
local load_avg=$(uptime | awk '{print $(NF-2)}' | tr -d ',')
local cpu_cores=$(nproc)
if (( $(echo "$load_avg > $cpu_cores * 2" | bc -l 2>/dev/null || echo 0) )); then
    log_warn "系统负载过高: $load_avg (CPU核心数: $cpu_cores)"
    ((issues++))
fi

# 检查重要服务状态
local services=("pveproxy" "pvedaemon" "pvestatd")
for service in "${services[@]}"; do
    if ! systemctl is-active "$service" &>/dev/null; then
        log_warn "服务状态异常: $service"
        ((issues++))
    fi
done

if (( issues == 0 )); then
    log_success "健康检查通过，系统运行正常"
else
    log_warn "发现 $issues 个潜在问题"
fi
```

}

# 一键配置

quick_setup() {
log_step “开始一键配置…”

```
local success=0
local total=3

if change_sources; then
    ((success++))
fi

if remove_subscription_popup; then
    ((success++))
fi

if update_system; then
    ((success++))
fi

if (( success == total )); then
    log_success "一键配置完成 ($success/$total)"
else
    log_warn "一键配置部分完成 ($success/$total)"
fi
```

}

# 显示菜单

show_menu() {
echo -e “${MAGENTA}╭─────────────────────────────╮${NC}”
echo -e “${MAGENTA}│         功能选择            │${NC}”
echo -e “${MAGENTA}╰─────────────────────────────╯${NC}”
echo -e “ ${CYAN}1.${NC} 换源 (Debian + PVE)”
echo -e “ ${CYAN}2.${NC} 删除订阅弹窗”
echo -e “ ${CYAN}3.${NC} 合并 local-lvm ${RED}[危险操作]${NC}”
echo -e “ ${CYAN}4.${NC} 删除 swap 分区”
echo -e “ ${CYAN}5.${NC} 更新系统”
echo -e “ ${CYAN}6.${NC} 显示系统信息”
echo -e “ ${CYAN}7.${NC} 健康检查”
echo -e “ ${CYAN}8.${NC} 一键配置 (1+2+5)”
echo -e “ ${CYAN}0.${NC} 退出程序”
echo
}

# 处理用户输入

handle_choice() {
local choice=”$1”

```
case "$choice" in
    1) change_sources ;;
    2) remove_subscription_popup ;;
    3) merge_local_storage ;;
    4) remove_swap ;;
    5) update_system ;;
    6) show_system_info ;;
    7) check_system_health ;;
    8) quick_setup ;;
    0) log_info "程序退出"; exit 0 ;;
    *) log_error "无效选择: $choice" ;;
esac
```

}

# 主程序

main() {
# 解析命令行参数
while [[ $# -gt 0 ]]; do
case $1 in
–dry-run)
DRY_RUN=true
log_info “启用 Dry-run 模式”
;;
–help|-h)
echo “用法: $0 [选项]”
echo “选项:”
echo “  –dry-run    模拟执行模式”
echo “  –help,-h    显示此帮助信息”
exit 0
;;
*)
log_error “未知参数: $1”
exit 1
;;
esac
shift
done

```
# 初始化检查
check_root
check_pve_version

# 主循环
while true; do
    show_banner
    show_menu
    
    local choice
    read -rp "请输入选择 [0-8]: " choice
    echo
    
    handle_choice "$choice"
    
    echo
    read -rp "按回车键返回主菜单..." -r
    echo
done
```

}

# 错误处理

trap ‘log_error “脚本执行被中断”; exit 1’ INT TERM

# 启动主程序

main “$@”
