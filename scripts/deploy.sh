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
CLUSTER_CONTEXT=""

# 设置集群context（根据实际情况修改）
case $ENV in
    pre-prod)
        CLUSTER_CONTEXT="kind-pre-prod"
        NAMESPACE="pre-release"
        ;;
    prod)
        CLUSTER_CONTEXT="kind-prod"
        NAMESPACE="production"
        ;;
    *)
        usage
        ;;
esac

echo -e "${YELLOW}开始部署到 $ENV 环境...${NC}"

# 加载环境变量（从CI或本地文件）
if [ -f ".env.$ENV" ]; then
    source ".env.$ENV"
else
    echo -e "${RED}错误: 找不到 .env.$ENV 文件${NC}"
    exit 1
fi

# 替换secret中的变量
TMP_DIR=$(mktemp -d)
cp $ENV/overlays/wordpress/secrets-patch.yaml.template $TMP_DIR/secrets-patch.yaml

# 使用envsubst替换变量
envsubst < $ENV/overlays/wordpress/secrets-patch.yaml.template > $TMP_DIR/secrets-patch.yaml

# 创建临时kustomization
cp $ENV/overlays/wordpress/kustomization.yaml $TMP_DIR/
sed -i "s|secrets-patch.yaml|$TMP_DIR/secrets-patch.yaml|g" $TMP_DIR/kustomization.yaml

case $ACTION in
    dry-run)
        echo -e "${YELLOW}预检配置...${NC}"
        kubectl kustomize $TMP_DIR > /tmp/${ENV}-manifest.yaml
        kubectl apply --dry-run=client -f /tmp/${ENV}-manifest.yaml
        echo -e "${GREEN}配置验证通过${NC}"
        ;;
    
    apply)
        echo -e "${YELLOW}应用配置到 $ENV 环境...${NC}"
        kubectl apply -k $TMP_DIR --context=$CLUSTER_CONTEXT
        
        echo -e "${YELLOW}等待部署就绪...${NC}"
        kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE rollout status deployment/pre-wordpress --timeout=120s
        
        echo -e "${GREEN}部署完成！${NC}"
        ;;
    
    diff)
        echo -e "${YELLOW}显示配置差异...${NC}"
        kubectl diff -k $TMP_DIR --context=$CLUSTER_CONTEXT
        ;;
    
    *)
        usage
        ;;
esac

# 清理临时文件
rm -rf $TMP_DIR
