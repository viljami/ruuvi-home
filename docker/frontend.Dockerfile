FROM node:22-alpine AS builder

WORKDIR /app

# Set memory-efficient build environment
ENV NODE_ENV=production
ENV GENERATE_SOURCEMAP=false
ENV INLINE_RUNTIME_CHUNK=false
ENV IMAGE_INLINE_SIZE_LIMIT=0
ENV NODE_OPTIONS="--max-old-space-size=1024"

COPY frontend/package.json frontend/package-lock.json ./

# Install dependencies with memory optimizations
RUN npm ci --production=false --silent && \
    npm cache clean --force

COPY frontend/ .

# Build with memory constraints and verify output
RUN npm run build && \
    # Verify critical build files exist \
    test -f build/index.html && \
    test -f build/manifest.json && \
    test -d build/static && \
    # Check build size is reasonable (< 50MB) \
    [ $(du -sm build | cut -f1) -lt 50 ] && \
    echo "Build verification passed" && \
    rm -rf node_modules && \
    npm cache clean --force

FROM nginx:alpine

COPY --from=builder /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
