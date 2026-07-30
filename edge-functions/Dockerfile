FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --production=false

COPY tsconfig.json ./
COPY src/ ./src/

RUN npm run build

FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --production

COPY --from=builder /app/dist ./dist
COPY healthcheck.mjs ./

EXPOSE 3000

ENV NODE_ENV=production

# US-215: the image previously declared no HEALTHCHECK, so Docker could not tell a
# wedged process from a healthy one. Uses node rather than curl because
# node:20-alpine ships neither curl nor wget.
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD ["node", "healthcheck.mjs"]

CMD ["node", "dist/index.js"]
