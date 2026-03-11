#!/bin/bash
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [pre-prod|prod] [apply|dry-run|diff]"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

ENV=$1
ACTION=$2

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${YELLOW}项目根目录: $PROJECT_ROOT${NC}"

# 设置集群 context（根据你的实际配置）
CLUSTER_CONTEXT="context-cluster1"  # 你的 context 名称

# 设置环境和目录
case $ENV in
    pre-prod)
        NAMESPACE="pre-release"
        ENV_DIR="pre-prod/overlays/wordpress"
        ;;
    prod)
        NAMESPACE="production"
        ENV_DIR="prod/overlays/wordpress"
        ;;
    *)
        usage
        ;;
esac

echo -e "${YELLOW}使用 context: $CLUSTER_CONTEXT${NC}"
echo -e "${YELLOW}使用环境: $ENV${NC}"
echo -e "${YELLOW}使用命名空间: $NAMESPACE${NC}"
echo -e "${YELLOW}使用环境目录: $ENV_DIR${NC}"

# 检查 context 是否存在
if ! kubectl config get-contexts -o name | grep -q "^$CLUSTER_CONTEXT$"; then
    echo -e "${RED}错误: context '$CLUSTER_CONTEXT' 不存在${NC}"
    echo -e "${YELLOW}可用的 contexts:${NC}"
    kubectl config get-contexts -o name
    exit 1
fi

# 检查环境目录是否存在
if [ ! -d "$PROJECT_ROOT/$ENV_DIR" ]; then
    echo -e "${RED}错误: 找不到环境目录 $PROJECT_ROOT/$ENV_DIR${NC}"
    exit 1
fi

# 加载环境变量
ENV_FILE="$PROJECT_ROOT/.env.$ENV"
if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}加载环境变量文件 $ENV_FILE${NC}"
    set -a  # 自动导出所有变量
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}错误: 找不到 $ENV_FILE 文件${NC}"
    echo -e "请创建该文件，例如："
    cat << EOF
# 示例 .env.$ENV 内容：
PRE_DB_PASSWORD="your_password"
PRE_REDIS_PASSWORD="your_redis_password"
PRE_AUTH_KEY="your_auth_key"
# ... 其他变量
EOF
    exit 1
fi

# 先测试 kustomize 是否正常工作
echo -e "${YELLOW}测试 kustomize 构建...${NC}"
cd "$PROJECT_ROOT"
if kubectl kustomize "$ENV_DIR" > /dev/null; then
    echo -e "${GREEN}✅ kustomize 构建成功${NC}"
else
    echo -e "${RED}❌ kustomize 构建失败${NC}"
    echo -e "${YELLOW}调试信息:${NC}"
    echo "当前目录: $(pwd)"
    echo "目录内容:"
    ls -la
    echo -e "\n$ENV_DIR 目录内容:"
    ls -la "$ENV_DIR" 2>/dev/null || echo "目录不存在"
    exit 1
fi

case $ACTION in
    dry-run)
        echo -e "${YELLOW}预检配置...${NC}"
        
        # 生成最终的YAML
        MANIFEST_FILE="/tmp/${ENV}-manifest.yaml"
        if kubectl kustomize "$ENV_DIR" > "$MANIFEST_FILE"; then
            echo -e "${GREEN}✅ 配置生成成功${NC}"
            
            # 显示生成的资源统计
            echo -e "${GREEN}生成的资源:${NC}"
            grep -E "^kind:" "$MANIFEST_FILE" | sort | uniq -c
            
            # 显示环境变量是否被正确替换（检查几个关键字段）
            echo -e "${YELLOW}验证环境变量替换:${NC}"
            echo "检查 MySQL 密码是否被替换:"
            grep -A 2 "name: mysql-credentials" "$MANIFEST_FILE" || echo "未找到 mysql-credentials"
            
            # 进行dry-run验证
            echo -e "${YELLOW}验证配置...${NC}"
            if kubectl apply --dry-run=client -f "$MANIFEST_FILE" --context=$CLUSTER_CONTEXT; then
                echo -e "${GREEN}✅ 配置验证通过${NC}"
                echo -e "完整的manifest已保存到: $MANIFEST_FILE"
                echo -e "${YELLOW}查看完整配置: cat $MANIFEST_FILE${NC}"
            else
                echo -e "${RED}❌ 配置验证失败${NC}"
                exit 1
            fi
        else
            echo -e "${RED}❌ 配置生成失败${NC}"
            exit 1
        fi
        ;;
    
    apply)
        echo -e "${YELLOW}应用配置到 $ENV 环境...${NC}"
        
        # 先确保namespace存在
        if ! kubectl --context=$CLUSTER_CONTEXT get namespace $NAMESPACE &>/dev/null; then
            echo -e "${YELLOW}创建 namespace: $NAMESPACE${NC}"
            kubectl --context=$CLUSTER_CONTEXT create namespace $NAMESPACE
        fi
        
        # 应用配置
        echo -e "${YELLOW}执行: kubectl apply -k $ENV_DIR --context=$CLUSTER_CONTEXT${NC}"
        if kubectl apply -k "$ENV_DIR" --context=$CLUSTER_CONTEXT; then
            echo -e "${GREEN}✅ 配置应用成功${NC}"
            
            # 等待部署就绪
            DEPLOYMENT_NAME="${ENV}-wordpress"
            echo -e "${YELLOW}等待部署 $DEPLOYMENT_NAME 就绪...${NC}"
            
            # 检查 deployment 是否存在
            if kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE get deployment $DEPLOYMENT_NAME &>/dev/null; then
                kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE rollout status deployment/$DEPLOYMENT_NAME --timeout=120s || true
            else
                echo -e "${YELLOW}Deployment $DEPLOYMENT_NAME 不存在，可能是命名不同，查看所有 deployments:${NC}"
                kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE get deployments
            fi
            
            # 显示部署状态
            echo -e "${YELLOW}当前Pod状态:${NC}"
            kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE get pods
            
            echo -e "${GREEN}✅ 部署完成！${NC}"
        else
            echo -e "${RED}❌ 配置应用失败${NC}"
            exit 1
        fi
        ;;
    
    diff)
        echo -e "${YELLOW}显示配置差异...${NC}"
        kubectl diff -k "$ENV_DIR" --context=$CLUSTER_CONTEXT || true
        ;;
    
    *)
        usage
        ;;
esac

echo -e "${GREEN}操作完成！${NC}"
