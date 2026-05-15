# Sub-Store-Front-End 静态资源镜像
# 构建产物 dist/ 已在 CI 流程的 pnpm build 步骤生成
# 此处仅将静态文件拷贝到 nginx，便于 buildx 多架构快速构建
FROM nginx:alpine

# 替换默认站点配置，启用 SPA history 模式 fallback（解决直接访问/刷新 /subs 等路径 404 问题）
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 拷贝构建产物到 nginx 默认站点目录
COPY dist/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
