# backend/Dockerfile
# Use Node's official image for a small runtime environment
FROM node:18-alpine

# Patch OS vulnerabilities
RUN apk update && apk upgrade --no-cache

# Create app directory
WORKDIR /app

# Install dependencies based on the package manifest first so we can leverage layer caching
COPY package*.json ./
RUN npm ci --only=production
# Bundle app source
COPY . .

# Define environment defaults; these can be overridden by compose or runtime variables
ENV NODE_ENV=production
ENV PORT=5000

# Expose port the app listens on
EXPOSE 5000

# Start the application
CMD ["node", "src/index.js"]
