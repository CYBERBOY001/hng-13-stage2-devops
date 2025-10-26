FROM node:18-alpine

RUN apk --no-cache add curl

WORKDIR /app

COPY package*.json ./

RUN npm install --production --no-optional && npm cache clean --force

COPY . .

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/healthz || exit 1

CMD ["node", "server.js"]