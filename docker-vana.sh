#!/bin/bash

# DLP Validator 安装路径
DLP_PATH="/root/vana-dlp-chatgpt"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 在Ubuntu 22.04容器中安装并运行DLP Validator节点
function install_dlp_node() {
    echo "在Ubuntu 22.04容器中安装并运行DLP Validator节点..."
    docker run -d --name dlp-validator-container ubuntu:22.04 /bin/bash -c '
    # 安装依赖
    apt update && apt upgrade -y
    apt install -y curl wget jq make gcc nano git software-properties-common

    # 安装Python和Poetry
    add-apt-repository ppa:deadsnakes/ppa -y
    apt update
    apt install -y python3.11 python3.11-venv python3.11-dev python3-pip
    curl -sSL https://install.python-poetry.org | python3 -
    echo "export PATH=\"/root/.local/bin:\$PATH\"" >> ~/.bashrc
    source ~/.bashrc

    # 安装Node.js和npm
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # 安装PM2
    npm install pm2@latest -g

    # 克隆仓库并安装依赖
    git clone https://github.com/vana-com/vana-dlp-chatgpt.git $DLP_PATH
    cd $DLP_PATH
    poetry install
    pip install vana

    # 创建钱包
    vanacli wallet create --wallet.name default --wallet.hotkey default

    # 导出私钥
    vanacli wallet export_private_key --wallet.name default --wallet.coldkey default > /root/coldkey.txt
    vanacli wallet export_private_key --wallet.name default --wallet.hotkey default > /root/hotkey.txt

    # 生成加密密钥
    ./keygen.sh

    # 将公钥写入.env文件
    PUBLIC_KEY=$(cat $DLP_PATH/public_key_base64.asc)
    echo "PRIVATE_FILE_ENCRYPTION_PUBLIC_KEY_BASE64=\"$PUBLIC_KEY\"" >> $DLP_PATH/.env

    # 部署智能合约
    cd /root
    git clone https://github.com/Josephtran102/vana-dlp-smart-contracts
    cd vana-dlp-smart-contracts
    npm install -g yarn
    yarn install
    cp .env.example .env
    nano .env
    npx hardhat deploy --network moksha --tags DLPDeploy

    # 注册验证器
    cd $DLP_PATH
    ./vanacli dlp register_validator --stake_amount 10
    HOTKEY_ADDRESS=$(./vanacli wallet show --wallet.name default --wallet.hotkey default | grep "SS58 Address" | awk "{print \$NF}")
    ./vanacli dlp approve_validator --validator_address="$HOTKEY_ADDRESS"

    # 创建.env文件
    cat <<EOF > $DLP_PATH/.env
OD_CHAIN_NETWORK=moksha
OD_CHAIN_NETWORK_ENDPOINT=https://rpc.moksha.vana.org
EOF
    echo "请手动编辑 $DLP_PATH/.env 文件，添加 OPENAI_API_KEY, DLP_MOKSHA_CONTRACT, 和 DLP_TOKEN_MOKSHA_CONTRACT"
    read -p "编辑完成后按回车继续"

    # 创建PM2配置文件
    cat <<EOF > $DLP_PATH/ecosystem.config.js
module.exports = {
  apps: [{
    name: "vana-validator",
    script: "poetry",
    args: "run python -m chatgpt.nodes.validator",
    cwd: "$DLP_PATH",
    interpreter: "none",
    env: {
      PATH: "/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$DLP_PATH/.venv/bin",
      PYTHONPATH: "$DLP_PATH",
    },
    restart_delay: 10000,
    max_restarts: 10,
    autorestart: true,
    watch: false,
  }],
};
EOF

    # 启动验证器
    pm2 start $DLP_PATH/ecosystem.config.js
    pm2 save

    # 保持容器运行
    tail -f /dev/null
    '

    echo "DLP Validator 容器已启动并在后台运行。"
    echo "要进入容器，请使用命令: docker exec -it dlp-validator-container /bin/bash"
}

# 查看节点日志
function check_node() {
    docker exec -it dlp-validator-container pm2 logs vana-validator
}

# 卸载节点
function uninstall_node() {
    echo "卸载 DLP Validator 节点..."
    docker stop dlp-validator-container
    docker rm dlp-validator-container
    echo "DLP Validator 节点已删除。"
}

# 主菜单
function main_menu() {
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "========================= VANA DLP Validator 节点安装 ======================================="
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"    
    echo "请选择要执行的操作:"
    echo "1. 安装 DLP Validator 节点"
    echo "2. 查看节点日志"
    echo "3. 删除节点"
    read -p "请输入选项（1-3）: " OPTION
    case $OPTION in
    1) install_dlp_node ;;
    2) check_node ;;
    3) uninstall_node ;;
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
main_menu
