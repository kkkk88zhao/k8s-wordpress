#!/bin/bash

ENV=$1
if [ "$ENV" == "pre-prod" ]; then
    CONTEXT="kind-pre-prod"
    NAMESPACE="pre-release"
    DOMAIN="pre.wordpress.local"
else
    CONTEXT="kind-prod"
    NAMESPACE="production"
    DOMAIN="wordpress.prod.com"
fi

echo "🔍 验证 $ENV 环境..."

# 1. 检查Pod状态
echo "📦 Pod状态:"
kubectl --context=$CONTEXT -n $NAMESPACE get pods

# 2. 检查Service
echo "🔌 Service:"
kubectl --context=$CONTEXT -n $NAMESPACE get svc

# 3. 检查Endpoint
echo "🌐 Endpoints:"
kubectl --context=$CONTEXT -n $NAMESPACE get endpoints

# 4. 检查PVC
echo "💾 PVC状态:"
kubectl --context=$CONTEXT -n $NAMESPACE get pvc

# 5. 测试数据库连接
echo "🗄️ 测试数据库连接..."
POD_NAME=$(kubectl --context=$CONTEXT -n $NAMESPACE get pod -l app=wordpress -o jsonpath="{.items[0].metadata.name}")
kubectl --context=$CONTEXT -n $NAMESPACE exec $POD_NAME -- wp db check --allow-root || echo "⚠️ 数据库检查失败"

# 6. 测试Redis连接
echo "⚡ 测试Redis连接..."
kubectl --context=$CONTEXT -n $NAMESPACE exec $POD_NAME -- wp redis info --allow-root || echo "⚠️ Redis连接失败"

# 7. HTTP健康检查（如果有Ingress）
if kubectl --context=$CONTEXT get ingress -n $NAMESPACE &>/dev/null; then
    echo "🌍 HTTP健康检查..."
    curl -f -H "Host: $DOMAIN" http://localhost/health && echo "✅ 健康检查通过"
fi

echo "✅ 验证完成！"
