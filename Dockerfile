FROM node:22.23.2-bookworm-slim
WORKDIR /app
COPY --chown=node:node package.json ./
COPY --chown=node:node server ./server
RUN mkdir /app/data && chown node:node /app/data
USER node
EXPOSE 5295
CMD ["node", "server/main.mjs"]
