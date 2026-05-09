# Build stage
FROM node:18-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM nginxinc/nginx-unprivileged:alpine

# Remove default static files (need to be root to remove files from /usr/share/nginx/html if they exist, but actually for unprivileged nginx we can just copy)
# Let's switch to root just to clean up if needed, though unprivileged nginx might not have files there.
USER root
RUN apk update && apk upgrade --no-cache && \
    rm -rf /usr/share/nginx/html/*

# Copy custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy React build
COPY --from=build /app/dist /usr/share/nginx/html

# Switch back to non-root user
USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]