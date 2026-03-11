#!/bin/bash

ENV=$1
VERSION=$2  # Git commit hash

if [ -z "$ENV" ] || [ -z "$VERSION" ]; then
    echo "Usage: $0 [pre-prod|prod] <git-commit-hash>"
    exit 1
fi

echo "🔄 回滚 $ENV 环境到版本 $VERSION..."

# 保存当前分支
CURRENT_BRANCH=$(git branch --show-current)

# 切换到目标版本
git checkout $VERSION

# 部署指定版本
case $ENV in
    pre-prod)
        kubectl apply -k pre-prod/ --context=kind-pre-prod
        ;;
    prod)
        kubectl apply -k prod/ --context=kind-prod
        ;;
esac

# 切回原分支
git checkout $CURRENT_BRANCH

echo "✅ 回滚完成！"
